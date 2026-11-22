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
    var documents: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    var sceneIndex: Int { project.scenes.firstIndex { $0.id == selectedSceneID } ?? 0 }
    var selected: TextScene { project.scenes[sceneIndex] }

    init() {
        load()
        selectedSceneID = project.scenes.first?.id
    }
    func updateScene(_ change: (inout TextScene) -> Void) {
        guard !project.scenes.isEmpty else { return }
        change(&project.scenes[sceneIndex]); save()
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
    func save() {
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
