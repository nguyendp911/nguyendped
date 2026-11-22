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
    private let previousFilename = "previous-project.json"
    private var scheduledSave: DispatchWorkItem?
    private(set) var hasEditedCurrentProject = false

    var documents: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    var sceneIndex: Int { project.scenes.firstIndex { $0.id == selectedSceneID } ?? 0 }
    var selected: TextScene { project.scenes[sceneIndex] }
    var hasPreviousDraft: Bool {
        FileManager.default.fileExists(atPath: documents.appendingPathComponent(previousFilename).path)
    }

    init() {
        // Never silently resume the previous movie and append new samples to it.
        // Preserve the last session separately; opening it is an explicit user action.
        let file = documents.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: file.path) {
            let backup = documents.appendingPathComponent(previousFilename)
            if let bytes = try? Data(contentsOf: file),
               let old = try? JSONDecoder().decode(StudioProject.self, from: bytes),
               !old.scenes.isEmpty {
                try? bytes.write(to: backup, options: .atomic)
                try? FileManager.default.removeItem(at: file)
            }
        }
        project = StudioProject()
        selectedSceneID = project.scenes.first?.id
    }

    func updateScene(_ change: (inout TextScene) -> Void) {
        guard !project.scenes.isEmpty else { return }
        let oldText = project.scenes[sceneIndex].text
        let oldVoice = project.scenes[sceneIndex].voiceConfiguration
        change(&project.scenes[sceneIndex])
        hasEditedCurrentProject = true
        if project.scenes[sceneIndex].text != oldText || project.scenes[sceneIndex].voiceConfiguration != oldVoice {
            project.scenes[sceneIndex].captionCues = []
            // Prior synthesized speech and cue offsets can no longer be trusted
            // after an edit. Keep imported music but remove stale voiceover clips.
            project.audioClips.removeAll { $0.relativeFilename.hasPrefix("voiceover-") }
        }
        scheduleSave()
    }

    func addScene() {
        // A newly added scene inherits the current visual template.
        // Different styles are an explicit choice in the scene editor.
        let current = selected
        var scene = TextScene(text: "", style: current.style, noiseCount: current.noiseCount,
                              foreground: current.foreground, title: "Cảnh \(project.scenes.count + 1)",
                              textMotion: current.textMotion, scrollSpeed: current.scrollSpeed,
                              voiceConfiguration: current.voiceConfiguration)
        scene.duration = current.duration
        project.scenes.append(scene)
        selectedSceneID = scene.id
        project.audioClips.removeAll { $0.relativeFilename.hasPrefix("voiceover-") }
        save()
    }
    func duplicateScene() {
        var scene = selected
        scene.id = UUID()
        scene.title += " (bản sao)"
        scene.captionCues = []
        project.scenes.insert(scene, at: sceneIndex + 1)
        selectedSceneID = scene.id
        // Old synthesized narration no longer matches scene offsets.
        project.audioClips.removeAll { $0.relativeFilename.hasPrefix("voiceover-") }
        save()
    }
    func deleteScene() {
        guard project.scenes.count > 1 else { toast = "Cần giữ ít nhất một cảnh"; return }
        project.scenes.remove(at: sceneIndex)
        project.audioClips.removeAll { $0.relativeFilename.hasPrefix("voiceover-") }
        selectedSceneID = project.scenes.first?.id
        save()
    }
    func move(from: IndexSet, to: Int) {
        project.scenes.move(fromOffsets: from, toOffset: to)
        project.audioClips.removeAll { $0.relativeFilename.hasPrefix("voiceover-") }
        save()
    }

    func newProject() {
        scheduledSave?.cancel()
        scheduledSave = nil
        // Retain current work as the recoverable previous draft.
        if hasEditedCurrentProject {
            if let bytes = try? JSONEncoder().encode(project) {
                try? bytes.write(to: documents.appendingPathComponent(previousFilename), options: .atomic)
            }
        }
        project = StudioProject()
        selectedSceneID = project.scenes.first?.id
        exportedURL = nil
        renderProgress = 0
        hasEditedCurrentProject = false
        try? FileManager.default.removeItem(at: documents.appendingPathComponent(filename))
    }

    func restorePreviousProject() {
        guard let bytes = try? Data(contentsOf: documents.appendingPathComponent(previousFilename)),
              let restored = try? JSONDecoder().decode(StudioProject.self, from: bytes),
              !restored.scenes.isEmpty else {
            toast = "Không có bản nháp trước để mở."
            return
        }
        // Keep a recoverable copy of the current edit if it was changed.
        if hasEditedCurrentProject {
            try? JSONEncoder().encode(project).write(
                to: documents.appendingPathComponent("recovery-current-project.json"),
                options: .atomic)
        }
        scheduledSave?.cancel()
        scheduledSave = nil
        project = restored
        selectedSceneID = restored.scenes.first?.id
        exportedURL = nil
        renderProgress = 0
        hasEditedCurrentProject = true
        save()
        toast = "Đã mở bản nháp trước."
    }

    private func scheduleSave() {
        scheduledSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save() }
        scheduledSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
    }
    func save() {
        scheduledSave?.cancel()
        scheduledSave = nil
        hasEditedCurrentProject = true
        do {
            try JSONEncoder().encode(project).write(
                to: documents.appendingPathComponent(filename), options: .atomic)
        } catch { toast = "Không lưu được dự án: \(error.localizedDescription)" }
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

    /// A distinct synthesis utterance is recorded for each visible caption.
    /// The emitted PCM frames, not reading-speed guesses, define the cue times.
    func createTimedTrack(chunks: [String], configuration: VoiceConfiguration, output: URL) async throws -> [CaptionCue] {
        guard !chunks.isEmpty else { throw NarrationError.emptyAudio }
        let directory = output.deletingLastPathComponent()
        var fragments: [URL] = []
        defer { for file in fragments { try? FileManager.default.removeItem(at: file) } }
        for part in chunks {
            let file = directory.appendingPathComponent("voice-part-\(UUID().uuidString).caf")
            fragments.append(file)
            _ = try await create(text: part, configuration: configuration, output: file)
        }
        let first = try AVAudioFile(forReading: fragments[0])
        let format = first.processingFormat
        let sampleRate = format.sampleRate
        guard sampleRate > 0 else { throw NarrationError.emptyAudio }
        try? FileManager.default.removeItem(at: output)
        let destination = try AVAudioFile(
            forWriting: output, settings: first.fileFormat.settings,
            commonFormat: format.commonFormat, interleaved: format.isInterleaved
        )
        var position: AVAudioFramePosition = 0
        var cues: [CaptionCue] = []
        for (index, partFile) in fragments.enumerated() {
            let source = try AVAudioFile(forReading: partFile)
            guard source.processingFormat.sampleRate == sampleRate,
                  source.processingFormat.channelCount == format.channelCount,
                  source.processingFormat.commonFormat == format.commonFormat else {
                throw NarrationError.unsupportedBuffer
            }
            let begin = Double(position) / sampleRate
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096)!
            while source.framePosition < source.length {
                try source.read(into: buffer)
                guard buffer.frameLength > 0 else { break }
                try destination.write(from: buffer)
                position += AVAudioFramePosition(buffer.frameLength)
            }
            let finish = Double(position) / sampleRate
            cues.append(CaptionCue(text: chunks[index], startTime: begin, endTime: finish))
        }
        guard position > 0 else { throw NarrationError.emptyAudio }
        return cues
    }

    func create(text: String, configuration: VoiceConfiguration, output: URL) async throws -> Double {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw NarrationError.emptyAudio }
        let chosen = AVSpeechSynthesisVoice.speechVoices().first {
            $0.identifier == configuration.voiceIdentifier && $0.language.lowercased().hasPrefix("vi")
        }
        guard let vietnamese = chosen ?? AVSpeechSynthesisVoice(language: "vi-VN") else {
            throw NarrationError.missingVietnameseVoice
        }
        try? FileManager.default.removeItem(at: output)
        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = vietnamese
        utterance.rate = max(AVSpeechUtteranceMinimumSpeechRate,
                             min(AVSpeechUtteranceMaximumSpeechRate, configuration.rate))
        utterance.pitchMultiplier = max(0.5, min(2, configuration.pitch))
        utterance.volume = max(0, min(1, configuration.volume))
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


/// Lightweight on-device spoken preview: no video rendering or file writes.
/// Reuses the same voice/utterance parameters as export.
@MainActor
final class VoiceLivePreview: ObservableObject {
    private let synthesizer = AVSpeechSynthesizer()
    @Published private(set) var isSpeaking = false

    func play(text: String, configuration: VoiceConfiguration) {
        synthesizer.stopSpeaking(at: .immediate)
        let excerpt = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(250))
        guard !excerpt.isEmpty else { isSpeaking = false; return }
        let utterance = AVSpeechUtterance(string: excerpt)
        let chosen = AVSpeechSynthesisVoice.speechVoices().first {
            $0.identifier == configuration.voiceIdentifier && $0.language.lowercased().hasPrefix("vi")
        }
        utterance.voice = chosen ?? AVSpeechSynthesisVoice(language: "vi-VN")
        utterance.rate = max(AVSpeechUtteranceMinimumSpeechRate,
                             min(AVSpeechUtteranceMaximumSpeechRate, configuration.rate))
        utterance.pitchMultiplier = max(0.5, min(2, configuration.pitch))
        utterance.volume = max(0, min(1, configuration.volume))
        synthesizer.speak(utterance)
        isSpeaking = true
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }
}
