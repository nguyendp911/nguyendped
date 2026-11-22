import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import Photos

struct StudioView: View {
    @StateObject private var store = ProjectStore()
    @State private var tab: StudioTab = .create
    @State private var isImporting = false
    @State private var isSharing = false
    @State private var savedToPhotos = false
    @State private var savingToPhotos = false
    @State private var cancellation: RenderCancellation?
    @State private var isExporting = false
    @State private var previewPlaying = true
    @State private var previewTime: Double = 0
    @State private var selectedTemplate = "Love Message"
    @FocusState private var isEditingText: Bool

    enum StudioTab: String, CaseIterable { case create = "Tạo nhanh", scenes = "Timeline", audio = "Âm nhạc", export = "Xuất video" }

    var body: some View {
        ZStack {
            Color(red: 0.025, green: 0.035, blue: 0.075).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    preview
                    activeSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollIndicators(.hidden)
        }
        .preferredColorScheme(.dark)
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.audio, UTType(filenameExtension: "mp3") ?? .audio, UTType(filenameExtension: "wav") ?? .audio, UTType(filenameExtension: "m4a") ?? .audio], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls): if let url = urls.first { store.importAudio(url) }
            case .failure(let error): store.toast = error.localizedDescription
            }
        }
        .sheet(isPresented: $isSharing) {
            if let url = store.exportedURL { ShareSheet(items: [url]) }
        }
        .alert("Thông báo", isPresented: Binding(get: { store.toast != nil }, set: { if !$0 { store.toast = nil } })) {
            Button("Đóng", role: .cancel) { store.toast = nil }
        } message: { Text(store.toast ?? "") }
    }

    @ViewBuilder private var activeSection: some View {
        switch tab {
        case .create: quickCreator
        case .scenes: sceneEditor
        case .audio: audioEditor
        case .export: exportSettings
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.title2).foregroundStyle(.cyan)
            VStack(alignment: .leading, spacing: 2) {
                Text("ViePN")
                    .font(.system(size: 19, weight: .black, design: .rounded))
                    .tracking(1.1)
                    .lineLimit(1).minimumScaleFactor(0.75)
                Text("Motion Message Studio")
                    .font(.caption2).foregroundStyle(.gray).lineLimit(1)
            }
            Spacer(minLength: 2)
            // Navigation is an on-demand menu, not a persistent tab bar.
            Menu {
                ForEach(StudioTab.allCases, id: \.rawValue) { item in
                    Button {
                        tab = item
                    } label: {
                        if tab == item {
                            Label(item.rawValue, systemImage: "checkmark.circle.fill")
                        } else {
                            Text(item.rawValue)
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(tab.rawValue).lineLimit(1)
                    Image(systemName: "line.3.horizontal")
                }
                .font(.caption.bold())
                .foregroundStyle(.cyan)
                .padding(.horizontal, 10).padding(.vertical, 9)
                .background(.cyan.opacity(0.11), in: Capsule())
            }
            .accessibilityLabel("Chọn mục: \(tab.rawValue)")
        }
        .frame(maxWidth: .infinity)
    }

    private var preview: some View {
        VStack(spacing: 8) {
            AnimatedPreview(scene: store.selected, playing: previewPlaying && !isEditingText)
                .frame(height: 215)
                .clipShape(RoundedRectangle(cornerRadius: 15))
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(.cyan.opacity(0.20)))
            HStack {
                Button { previewPlaying.toggle() } label: {
                    Label(previewPlaying ? "Dừng" : "Phát",
                          systemImage: previewPlaying ? "pause.fill" : "play.fill")
                }
                Spacer()
                Text("\(store.selected.style.rawValue) • \(Int(store.selected.duration))s")
                    .font(.caption).foregroundStyle(.gray).lineLimit(1)
                Button { store.updateScene { $0.seed = UInt64.random(in: 1...UInt64.max) } } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
            }.buttonStyle(.bordered)
        }
    }

    private var quickCreator: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionTitle("01", "Thông điệp")
            TextEditor(text: Binding(get: { store.selected.text }, set: { text in store.updateScene { $0.text = String(text.prefix(2000)) } }))
                .font(.title3).scrollContentBackground(.hidden).frame(minHeight: 100)
                .focused($isEditingText)
                .padding(10).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
            HStack {
                Text("Ký tự nhiễu").foregroundStyle(.gray)
                Spacer()
                Text("\(store.selected.noiseCount)").monospacedDigit().foregroundStyle(.cyan)
            }
            Slider(value: Binding(get: { Double(store.selected.noiseCount) }, set: { n in store.updateScene { $0.noiseCount = Int(n) } }), in: 0...300, step: 10).tint(.cyan)
            sectionTitle("CHỮ", "Hướng chuyển động")
            Picker("Hiệu ứng văn bản", selection: Binding(
                get: { store.selected.textMotion },
                set: { value in store.updateScene { $0.textMotion = value } }
            )) {
                ForEach(TextMotion.allCases) { motion in
                    Text(motion.rawValue).tag(motion)
                }
            }
            .pickerStyle(.segmented)
            if store.selected.textMotion == .scrollUp {
                HStack {
                    Text("Tốc độ cuộn").foregroundStyle(.gray)
                    Spacer()
                    Text(String(format: "%.1fx", store.selected.scrollSpeed))
                        .foregroundStyle(.cyan).monospacedDigit()
                }
                Slider(value: Binding(
                    get: { store.selected.scrollSpeed },
                    set: { newValue in store.updateScene { $0.scrollSpeed = newValue } }
                ), in: 0.5...2.0, step: 0.1).tint(.cyan)
                Text("Cuộn chữ từ dưới lên, tự ngắt dòng khi nội dung dài.")
                    .font(.caption).foregroundStyle(.gray)
            }
            sectionTitle("02", "Chọn phong cách")
            styleGallery
            sectionTitle("03", "Thời lượng cảnh")
            HStack {
                Slider(value: Binding(get: { store.selected.duration }, set: { v in store.updateScene { $0.duration = v } }), in: 3...180, step: 1).tint(.cyan)
                Text("\(Int(store.selected.duration))s").monospacedDigit().frame(width: 38)
            }
            sectionTitle("04", "Tự động chia cảnh")
            Button { splitIntoScenes() } label: { Label("Chia câu thành các cảnh", systemImage: "text.alignleft") }.buttonStyle(.bordered)
            Text("Chia theo dấu câu, không dùng AI hay dịch vụ mạng. Văn bản gốc vẫn được giữ nguyên theo từng đoạn.").font(.caption).foregroundStyle(.gray)
            sectionTitle("05", "Mẫu dựng nhanh")
            Picker("Mẫu", selection: $selectedTemplate) {
                ForEach(["Love Message", "Cinematic Story", "Technology Intro", "Dark Fantasy", "Motivational Video", "Luxury Presentation"], id: \.self) { Text($0) }
            }.pickerStyle(.menu)
            Button("Áp dụng mẫu") { applyTemplate() }.buttonStyle(PrimaryButtonStyle())
            Button { tab = .export } label: { Label("Tiếp tục xuất video", systemImage: "arrow.right.circle.fill") }.buttonStyle(PrimaryButtonStyle())
        }
    }

    private var styleGallery: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(MotionStyle.allCases) { style in
                Button { store.updateScene { $0.style = style; $0.foreground = style.accent } } label: {
                    VStack(alignment: .leading, spacing: 9) {
                        Image(systemName: style.symbol).font(.system(size: 28)).foregroundStyle(style.accent.swiftUIColor)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(style.rawValue).font(.subheadline.bold()).foregroundStyle(.white).lineLimit(1)
                        Text(style.category).font(.caption2).foregroundStyle(.gray)
                    }
                    .padding(13).frame(maxWidth: .infinity, alignment: .leading)
                    .background(store.selected.style == style ? Color.cyan.opacity(0.16) : Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(store.selected.style == style ? .cyan : .clear, lineWidth: 1))
                }.buttonStyle(.plain)
            }
        }
    }

    private var sceneEditor: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack {
                sectionTitle("TIMELINE", "\(store.project.scenes.count) cảnh  •  \(Int(store.project.totalDuration)) giây")
                Spacer()
                Button { store.addScene() } label: { Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(.cyan) }
            }
            ForEach(Array(store.project.scenes.enumerated()), id: \.element.id) { index, scene in
                Button { store.selectedSceneID = scene.id } label: {
                    HStack(spacing: 12) {
                        Text(String(format: "%02d", index+1)).font(.caption.monospacedDigit()).foregroundStyle(.gray)
                        Image(systemName: scene.style.symbol).foregroundStyle(scene.style.accent.swiftUIColor)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(scene.title).font(.subheadline.bold()).foregroundStyle(.white)
                            Text(scene.text).font(.caption).foregroundStyle(.gray).lineLimit(1)
                        }
                        Spacer()
                        Text("\(Int(scene.duration))s").font(.caption.monospacedDigit()).foregroundStyle(.cyan)
                    }.padding(13).background(store.selectedSceneID == scene.id ? Color.cyan.opacity(0.14) : Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain)
            }
            Text("Chạm một cảnh để chỉnh trong Tạo nhanh. Có thể kéo đổi thứ tự qua nút bên dưới.").font(.caption).foregroundStyle(.gray)
            HStack {
                Button { store.duplicateScene() } label: { Label("Nhân đôi", systemImage: "plus.square.on.square") }
                Button(role: .destructive) { store.deleteScene() } label: { Label("Xóa", systemImage: "trash") }
            }.buttonStyle(.bordered)
            SceneReorderView(store: store)
            Button { tab = .create } label: { Label("Chỉnh cảnh đang chọn", systemImage: "slider.horizontal.3") }.buttonStyle(PrimaryButtonStyle())
        }
    }

    private var audioEditor: some View {
        VStack(alignment: .leading, spacing: 17) {
            sectionTitle("MUSIC STUDIO", "Nhạc nền & âm thanh")
            Button { isImporting = true } label: { Label("Nhập audio từ Files", systemImage: "plus.circle.fill") }.buttonStyle(PrimaryButtonStyle())
            if store.project.audioClips.isEmpty {
                Text("Chưa có nhạc. Bạn có thể tạo video không âm thanh hoặc nhập MP3, M4A, WAV từ Files.").font(.subheadline).foregroundStyle(.gray)
            }
            ForEach($store.project.audioClips) { $clip in
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "music.note").foregroundStyle(.cyan)
                        Text(clip.displayName).font(.subheadline.bold()).lineLimit(1)
                        Spacer()
                        Button(role: .destructive) { store.removeAudio(clip.id) } label: { Image(systemName: "trash") }
                    }
                    audioSlider("Vào video", value: $clip.startTime, max: max(1, store.project.totalDuration))
                    audioSlider("Cắt từ giây", value: $clip.sourceIn, max: max(1, clip.duration-0.2))
                    audioSlider("Âm lượng", value: Binding(get: { Double(clip.volume) }, set: { clip.volume = Float($0) }), max: 1)
                    HStack {
                        Text("Fade in").font(.caption).foregroundStyle(.gray)
                        Slider(value: $clip.fadeIn, in: 0...min(5, max(0.1, clip.duration/2))).tint(.cyan)
                        Text("\(clip.fadeIn, specifier: "%.1f")s").font(.caption.monospacedDigit())
                    }
                    HStack {
                        Text("Fade out").font(.caption).foregroundStyle(.gray)
                        Slider(value: $clip.fadeOut, in: 0...min(5, max(0.1, clip.duration/2))).tint(.cyan)
                        Text("\(clip.fadeOut, specifier: "%.1f")s").font(.caption.monospacedDigit())
                    }
                }.padding(14).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
            }
            Button("Lưu cài đặt audio") { store.save(); store.toast = "Đã lưu audio" }.buttonStyle(.bordered)
            Text("Hiện hỗ trợ nhập, đặt vị trí, điểm bắt đầu, âm lượng và fade. Chưa có waveform, beat detection, split hay crossfade editor.").font(.caption).foregroundStyle(.gray)
        }
    }

    private func audioSlider(_ title: String, value: Binding<Double>, max: Double) -> some View {
        HStack {
            Text(title).font(.caption).foregroundStyle(.gray).frame(width: 82, alignment: .leading)
            Slider(value: value, in: 0...max).tint(.cyan)
            Text("\(value.wrappedValue, specifier: "%.1f")").font(.caption.monospacedDigit()).frame(width: 35)
        }
    }

    private var exportSettings: some View {
        VStack(alignment: .leading, spacing: 17) {
            sectionTitle("EXPORT", "Thiết lập video")
            VStack(spacing: 14) {
                HStack {
                    Text("Khung hình"); Spacer()
                    Picker("Tỉ lệ", selection: $store.project.aspect) {
                        ForEach(VideoAspect.allCases) { Text($0.rawValue).tag($0) }
                    }.tint(.cyan)
                }
                HStack {
                    Text("Độ phân giải"); Spacer()
                    Picker("Độ rộng", selection: $store.project.width) {
                        Text("720p cơ bản").tag(720)
                        Text("1080p cơ bản").tag(1080)
                        Text("4K (rất nặng)").tag(2160)
                    }.tint(.cyan)
                }
                HStack {
                    Text("FPS"); Spacer()
                    Picker("FPS", selection: $store.project.fps) { Text("24").tag(24); Text("30").tag(30); Text("60").tag(60) }.tint(.cyan)
                }
            }.padding(14).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
            Text("Video: \(Int(store.project.totalDuration)) giây • \(store.project.scenes.count) cảnh • \(store.project.audioClips.count) audio clip").font(.subheadline).foregroundStyle(.gray)
            if isExporting {
                ProgressView(value: store.renderProgress).tint(.cyan)
                Text("Đang render \(Int(store.renderProgress * 100))% — giữ ứng dụng ở màn hình này").font(.caption).foregroundStyle(.gray)
                Button("Hủy xuất", role: .destructive) { cancellation?.cancel() }.buttonStyle(.bordered)
            } else {
                Button { beginExport() } label: { Label("Tạo MP4 H.264", systemImage: "film.stack") }.buttonStyle(PrimaryButtonStyle())
            }
            if let url = store.exportedURL {
                if savedToPhotos {
                    Label("Đã lưu video vào ứng dụng Ảnh", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green).font(.subheadline.bold())
                } else {
                    Button {
                        Task { await saveVideoToPhotos(url) }
                    } label: {
                        Label(savingToPhotos ? "Đang lưu vào Ảnh..." : "Lưu vào bộ sưu tập Ảnh",
                              systemImage: "photo.on.rectangle")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(savingToPhotos)
                }
                Button { isSharing = true } label: {
                    Label("Chia sẻ video (tùy chọn)", systemImage: "square.and.arrow.up")
                }.buttonStyle(.bordered)
                Text(url.lastPathComponent).font(.caption.monospaced()).foregroundStyle(.gray).textSelection(.enabled)
            }
            Text("Xuất bằng CPU/GPU trên máy; video dài hoặc 4K có thể mất nhiều thời gian và cần dung lượng trống. Đây chưa phải bộ xuất background có thể tiếp tục sau khi iOS đóng app.").font(.caption).foregroundStyle(.gray)
        }
        .onChange(of: store.project.width) { _ in store.save() }
        .onChange(of: store.project.fps) { _ in store.save() }
        .onChange(of: store.project.aspect) { _ in store.save() }
    }

    private func beginExport() {
        guard !isExporting else { return }
        store.save(); store.exportedURL = nil; store.renderProgress = 0
        savedToPhotos = false
        isExporting = true
        let token = RenderCancellation(); cancellation = token
        let snapshot = store.project
        let documents = store.documents
        Task {
            do {
                let url = try await VideoExporter().export(project: snapshot, documents: documents, cancellation: token) { p in
                    DispatchQueue.main.async { store.renderProgress = p }
                }
                store.exportedURL = url
                await saveVideoToPhotos(url)
            } catch { store.toast = error.localizedDescription }
            isExporting = false
        }
    }

    @MainActor
    private func saveVideoToPhotos(_ url: URL) async {
        guard !savingToPhotos else { return }
        savingToPhotos = true
        defer { savingToPhotos = false }
        let status = await withCheckedContinuation { (continuation: CheckedContinuation<PHAuthorizationStatus, Never>) in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { result in
                continuation.resume(returning: result)
            }
        }
        guard status == .authorized || status == .limited else {
            store.toast = "Ứng dụng chưa được cấp quyền thêm video vào Ảnh. Vào Cài đặt → ViePN Reveal → Ảnh để cấp quyền, rồi nhấn Lưu vào bộ sưu tập. File video vẫn còn trong ứng dụng."
            return
        }
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                } completionHandler: { success, error in
                    if success { continuation.resume(returning: ()) }
                    else {
                        continuation.resume(throwing: error ?? NSError(
                            domain: "ViePNReveal.Photos", code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "Không thể lưu video vào Ảnh"]))
                    }
                }
            }
            savedToPhotos = true
            store.toast = "Đã xuất và lưu video vào bộ sưu tập Ảnh!"
        } catch {
            store.toast = "Video đã render nhưng không lưu được vào Ảnh: \(error.localizedDescription). Bạn có thể thử lại bằng nút Lưu vào bộ sưu tập."
        }
    }

    private func splitIntoScenes() {
        let input = store.selected.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = input.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard parts.count > 1 else { store.toast = "Nhập nhiều câu, ngăn bằng dấu chấm hoặc xuống dòng"; return }
        let sceneStyle = store.selected.style
        store.project.scenes = parts.enumerated().map { index, content in
            TextScene(text: content, duration: min(18, max(5, Double(content.count) * 0.13)), style: index.isMultiple(of: 2) ? sceneStyle : MotionStyle.allCases[index % MotionStyle.allCases.count], title: "Cảnh \(index + 1)")
        }
        store.selectedSceneID = store.project.scenes.first?.id
        store.save()
        store.toast = "Đã tạo \(parts.count) cảnh"
    }

    private func applyTemplate() {
        let style: MotionStyle
        switch selectedTemplate {
        case "Cinematic Story": style = .cosmicSpace
        case "Technology Intro": style = .cyberMatrix
        case "Dark Fantasy": style = .magicRune
        case "Motivational Video": style = .kineticType
        case "Luxury Presentation": style = .metallic3D
        default: style = .goldenParticles
        }
        store.updateScene { $0.style = style; $0.foreground = style.accent }
        store.toast = "Đã áp dụng mẫu \(selectedTemplate)"
    }

    private func sectionTitle(_ number: String, _ title: String) -> some View {
        HStack(spacing: 10) {
            Text(number).font(.caption.monospaced()).foregroundStyle(.cyan)
            Text(title).font(.headline).foregroundStyle(.white)
        }
    }
}

struct SceneReorderView: View {
    @ObservedObject var store: ProjectStore
    var body: some View {
        DisclosureGroup("Đổi thứ tự cảnh") {
            List {
                ForEach(store.project.scenes) { scene in Text(scene.title) }
                    .onMove { indices, position in store.move(from: indices, to: position) }
            }.frame(height: min(250, CGFloat(store.project.scenes.count * 52 + 40))).scrollContentBackground(.hidden)
        }.font(.subheadline).tint(.cyan)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.bold()).frame(maxWidth: .infinity).padding(.vertical, 14)
            .foregroundStyle(.black).background(.cyan.opacity(configuration.isPressed ? 0.65 : 1), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

private struct AnimatedPreview: View {
    let scene: TextScene
    let playing: Bool
    private let origin = Date()

    var body: some View {
        GeometryReader { geometry in
            // Ten preview frames/second avoid recompositing huge UIImages
            // at the device display refresh rate while editing.
            TimelineView(.periodic(from: .now, by: 0.1)) { timeline in
                let phase = playing
                    ? timeline.date.timeIntervalSince(origin).truncatingRemainder(dividingBy: max(scene.duration, 0.5))
                    : 0
                let previewWidth: CGFloat = 340
                let previewHeight = previewWidth * geometry.size.height / max(geometry.size.width, 1)
                Image(uiImage: FrameRenderer.shared.render(
                    scene: scene, time: phase,
                    size: CGSize(width: previewWidth, height: previewHeight)))
                    .resizable()
                    .interpolation(.medium)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
            }
        }
    }
}
