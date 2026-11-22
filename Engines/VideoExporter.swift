import Foundation
import AVFoundation
import CoreImage
import UIKit

final class RenderCancellation {
    private let lock = NSLock()
    private var canceled = false
    func cancel() { lock.lock(); canceled = true; lock.unlock() }
    var isCanceled: Bool { lock.lock(); defer { lock.unlock() }; return canceled }
}

enum ExportFailure: LocalizedError {
    case canceled, writer(String), cannotAddVideo, invalidDimensions
    var errorDescription: String? {
        switch self {
        case .canceled: "Đã hủy xuất video"
        case .writer(let reason): "Không thể xuất video: \(reason)"
        case .cannotAddVideo: "Không thể tạo kênh hình ảnh"
        case .invalidDimensions: "Kích thước video không hợp lệ"
        }
    }
}

/// Frame-by-frame exporter: bounded memory; audio is muxed after rendering the video.
final class VideoExporter {
    func export(project: StudioProject, documents: URL, cancellation: RenderCancellation, progress: @escaping (Double) -> Void) async throws -> URL {
        let temp = FileManager.default.temporaryDirectory
        let silentURL = temp.appendingPathComponent(UUID().uuidString + "-silent.mp4")
        let finalURL = documents.appendingPathComponent("SecretText-\(Int(Date().timeIntervalSince1970)).mp4")
        let size = project.aspect.size(for: project.width)
        let fps = project.fps
        guard size.width > 0, size.height > 0, fps > 0 else { throw ExportFailure.invalidDimensions }
        defer { try? FileManager.default.removeItem(at: silentURL) }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try self.writeFrames(project: project, url: silentURL, size: size, fps: fps, cancellation: cancellation, progress: progress)
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
        if cancellation.isCanceled { throw ExportFailure.canceled }
        if project.audioClips.isEmpty {
            try FileManager.default.moveItem(at: silentURL, to: finalURL)
            progress(1)
            return finalURL
        }
        try await mixAudio(video: silentURL, project: project, documents: documents, output: finalURL, cancellation: cancellation)
        progress(1)
        return finalURL
    }

    private func writeFrames(project: StudioProject, url: URL, size: CGSize, fps: Int, cancellation: RenderCancellation, progress: @escaping (Double) -> Void) throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let compression: [String: Any] = [AVVideoAverageBitRateKey: project.width >= 1920 ? 12_000_000 : 5_000_000]
        let settings: [String: Any] = [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height), AVVideoCompressionPropertiesKey: compression]
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        video.expectsMediaDataInRealTime = false
        let attributes: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: Int(size.width), kCVPixelBufferHeightKey as String: Int(size.height), kCVPixelBufferIOSurfacePropertiesKey as String: [:]]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: attributes)
        guard writer.canAdd(video) else { throw ExportFailure.cannotAddVideo }
        writer.add(video)
        guard writer.startWriting() else { throw ExportFailure.writer(writer.error?.localizedDescription ?? "Không thể bắt đầu") }
        writer.startSession(atSourceTime: .zero)
        let renderer = FrameRenderer()
        let ciContext = CIContext(options: [.useSoftwareRenderer: false])
        let totalFrames = max(1, Int(ceil(project.totalDuration * Double(fps))))
        var currentScene = 0
        var sceneStart = 0.0
        for frame in 0..<totalFrames {
            if cancellation.isCanceled { writer.cancelWriting(); throw ExportFailure.canceled }
            let t = Double(frame) / Double(fps)
            while currentScene < project.scenes.count-1 && t >= sceneStart + project.scenes[currentScene].duration {
                sceneStart += project.scenes[currentScene].duration
                currentScene += 1
            }
            while !video.isReadyForMoreMediaData {
                if cancellation.isCanceled { writer.cancelWriting(); throw ExportFailure.canceled }
                Thread.sleep(forTimeInterval: 0.007)
            }
            var frameWritten = false
            autoreleasepool {
                let image = renderer.render(scene: project.scenes[currentScene], time: t - sceneStart, size: size)
                guard let cgImage = image.cgImage else { return }
                var buffer: CVPixelBuffer?
                if let pool = adaptor.pixelBufferPool { CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) }
                if let buffer {
                    ciContext.render(CIImage(cgImage: cgImage), to: buffer)
                    let stamp = CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps))
                    frameWritten = adaptor.append(buffer, withPresentationTime: stamp)
                }
            }
            if !frameWritten || writer.status == .failed {
                writer.cancelWriting()
                throw ExportFailure.writer(writer.error?.localizedDescription ?? "Lỗi ghi khung hình hoặc thiếu bộ nhớ")
            }
            if frame % max(1, fps / 2) == 0 { progress(Double(frame) / Double(totalFrames) * 0.9) }
        }
        video.markAsFinished()
        let semaphore = DispatchSemaphore(value: 0)
        writer.finishWriting { semaphore.signal() }
        semaphore.wait()
        guard writer.status == .completed else { throw ExportFailure.writer(writer.error?.localizedDescription ?? "Không thể hoàn tất") }
    }

    private func mixAudio(video: URL, project: StudioProject, documents: URL, output: URL, cancellation: RenderCancellation) async throws {
        let composition = AVMutableComposition()
        let videoAsset = AVURLAsset(url: video)
        guard let sourceVideo = videoAsset.tracks(withMediaType: .video).first,
              let destinationVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw ExportFailure.writer("Không thể đọc video tạm")
        }
        try destinationVideo.insertTimeRange(CMTimeRange(start: .zero, duration: videoAsset.duration), of: sourceVideo, at: .zero)
        destinationVideo.preferredTransform = sourceVideo.preferredTransform
        let audioMix = AVMutableAudioMix()
        var parameters: [AVMutableAudioMixInputParameters] = []
        for clip in project.audioClips {
            let file = documents.appendingPathComponent(clip.relativeFilename)
            let asset = AVURLAsset(url: file)
            guard let source = asset.tracks(withMediaType: .audio).first,
                  let destination = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
            let start = max(0, clip.startTime)
            let sourceIn = max(0, clip.sourceIn)
            let available = min(clip.duration, CMTimeGetSeconds(asset.duration) - sourceIn, project.totalDuration - start)
            guard available > 0 else { composition.removeTrack(destination); continue }
            try destination.insertTimeRange(CMTimeRange(start: CMTime(seconds: sourceIn, preferredTimescale: 600), duration: CMTime(seconds: available, preferredTimescale: 600)), of: source, at: CMTime(seconds: start, preferredTimescale: 600))
            let p = AVMutableAudioMixInputParameters(track: destination)
            let volume = max(0, min(1, clip.volume))
            p.setVolume(volume, at: CMTime(seconds: start, preferredTimescale: 600))
            if clip.fadeIn > 0 {
                p.setVolumeRamp(fromStartVolume: 0, toEndVolume: volume, timeRange: CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600), duration: CMTime(seconds: min(clip.fadeIn, available/2), preferredTimescale: 600)))
            }
            if clip.fadeOut > 0 {
                let fade = min(clip.fadeOut, available/2)
                p.setVolumeRamp(fromStartVolume: volume, toEndVolume: 0, timeRange: CMTimeRange(start: CMTime(seconds: start+available-fade, preferredTimescale: 600), duration: CMTime(seconds: fade, preferredTimescale: 600)))
            }
            parameters.append(p)
        }
        audioMix.inputParameters = parameters
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else { throw ExportFailure.writer("Không có bộ xuất audio") }
        exporter.outputURL = output
        exporter.outputFileType = .mp4
        exporter.audioMix = audioMix
        exporter.shouldOptimizeForNetworkUse = true
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            exporter.exportAsynchronously { continuation.resume() }
        }
        if cancellation.isCanceled { try? FileManager.default.removeItem(at: output); throw ExportFailure.canceled }
        guard exporter.status == .completed else { throw ExportFailure.writer(exporter.error?.localizedDescription ?? "Ghép nhạc thất bại") }
    }
}
