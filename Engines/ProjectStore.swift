import Foundation
import AVFoundation
import UniformTypeIdentifiers

@MainActor final class ProjectStore: ObservableObject {
    @Published var project = StudioProject()
    @Published var selectedSceneID: UUID?
    @Published var toast: String?
    @Published var isRendering = false
    @Published var renderProgress: Double = 0
    @Published var exportedURL: URL?
    @Published var renderError: String?
    private let filename = "project.json"
    private var scheduledSave: DispatchWorkItem?
    var documents: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    var sceneIndex: Int { project.scenes.firstIndex { $0.id == selectedSceneID } ?? 0 }
    var selected: TextScene { project.scenes[sceneIndex] }

    init() {
        load()
        selectedSceneID = project.scenes.first?.id
    }
    func updateScene(_ change: (inout TextScene) -> Void) {
        guard !project.scenes.isEmpty else { return }
        change(&project.scenes[sceneIndex]); scheduleSave()
    }
    func addScene() {
        let scene = TextScene(text: "Thông điệp mới", style: MotionStyle.allCases[project.scenes.count % MotionStyle.allCases.count], title: "Cảnh \(project.scenes.count + 1)")
        project.scenes.append(scene); selectedSceneID = scene.id; save()
    }
    func duplicateScene() {
        var scene = selected; scene.id = UUID(); scene.title += " (bản sao)"
        project.scenes.insert(scene, at: sceneIndex+1); selectedSceneID = scene.id; save()
    }
    func deleteScene() {
        guard project.scenes.count > 1 else { toast = "Cần giữ ít nhất một cảnh"; return }
        project.scenes.remove(at: sceneIndex); selectedSceneID = project.scenes.first?.id; save()
    }
    func move(from: IndexSet, to: Int) { project.scenes.move(fromOffsets: from, toOffset: to); save() }
    private func scheduleSave() {
        scheduledSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save() }
        scheduledSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
    }
    func save() {
        scheduledSave?.cancel()
        scheduledSave = nil
        do { try JSONEncoder().encode(project).write(to: documents.appendingPathComponent(filename), options: .atomic) }
        catch { toast = "Không lưu được dự án: \(error.localizedDescription)" }
    }
    func load() {
        let url = documents.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode(StudioProject.self, from: data), !decoded.scenes.isEmpty else { return }
        project = decoded
    }
    func importAudio(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let name = UUID().uuidString + "." + url.pathExtension.lowercased()
            let destination = documents.appendingPathComponent(name)
            try FileManager.default.copyItem(at: url, to: destination)
            let asset = AVURLAsset(url: destination)
            let seconds = CMTimeGetSeconds(asset.duration)
            guard seconds.isFinite && seconds > 0 else { try? FileManager.default.removeItem(at: destination); toast = "Tệp âm thanh không hợp lệ"; return }
            project.audioClips.append(AudioClip(relativeFilename: name, displayName: url.lastPathComponent, duration: seconds))
            save()
        } catch { toast = "Không nhập được nhạc: \(error.localizedDescription)" }
    }
    func removeAudio(_ id: UUID) {
        project.audioClips.removeAll { $0.id == id }; save()
    }
}


// Renders the iPhone's installed Vietnamese speech voice into a real CAF audio
// file. Timing is measured from emitted PCM frames, never estimated from words.
final class NarrationRenderSession {
    private let lock = NSLock()
    private let outputURL: URL
    private var continuation: CheckedContinuation<Double, Error>?
    private var audioFile: AVAudioFile?
    private var totalFrames: AVAudioFramePosition = 0
    private var sampleRate: Double = 0
    private var ended = false

    init(outputURL: URL, continuation: CheckedContinuation<Double, Error>) {
        self.outputURL = outputURL
        self.continuation = continuation
    }

    func accept(_ buffer: AVAudioBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard !ended else { return }
        guard let pcm = buffer as? AVAudioPCMBuffer else {
            finish(.failure(NarrationError.unsupportedBuffer))
            return
        }
        if pcm.frameLength == 0 {
            audioFile = nil
            let seconds = sampleRate > 0 ? Double(totalFrames) / sampleRate : 0
            if seconds <= 0 {
                finish(.failure(NarrationError.emptyAudio))
            } else {
                finish(.success(seconds))
            }
            return
        }
        do {
            if audioFile == nil {
                sampleRate = pcm.format.sampleRate
                audioFile = try AVAudioFile(forWriting: outputURL, settings: pcm.format.settings)
            }
            try audioFile?.write(from: pcm)
            totalFrames += AVAudioFramePosition(pcm.frameLength)
        } catch {
            audioFile = nil
            finish(.failure(error))
        }
    }

    private func finish(_ result: Result<Double, Error>) {
        guard !ended else { return }
        ended = true
        let savedContinuation = continuation
        continuation = nil
        savedContinuation?.resume(with: result)
    }
}

enum NarrationError: LocalizedError {
    case missingVietnameseVoice, emptyAudio, unsupportedBuffer
    var errorDescription: String? {
        switch self {
        case .missingVietnameseVoice:
            return "Thiết bị chưa có giọng đọc Tiếng Việt hỗ trợ tạo audio. Hãy kiểm tra các giọng đọc trong Cài đặt iPhone."
        case .emptyAudio: return "Giọng đọc không tạo ra dữ liệu âm thanh."
        case .unsupportedBuffer: return "Định dạng âm thanh giọng đọc chưa được hỗ trợ."
        }
    }
}

@MainActor
final class VietnameseNarrationEngine {
    private let synth = AVSpeechSynthesizer()

    func create(text: String, rate: Float, output: URL) async throws -> Double {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw NarrationError.emptyAudio }
        guard let vietnamese = AVSpeechSynthesisVoice(language: "vi-VN") else {
            throw NarrationError.missingVietnameseVoice
        }
        try? FileManager.default.removeItem(at: output)
        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = vietnamese
        utterance.rate = max(0.40, min(0.60, rate))
        utterance.preUtteranceDelay = 0
        utterance.postUtteranceDelay = 0
        return try await withCheckedThrowingContinuation { continuation in
            let session = NarrationRenderSession(outputURL: output, continuation: continuation)
            synth.write(utterance) { buffer in
                session.accept(buffer)
            }
        }
    }
}
