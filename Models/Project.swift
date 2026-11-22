import Foundation
import SwiftUI

struct RGBAColor: Codable, Hashable {
    var red: Double; var green: Double; var blue: Double
    var uiColor: UIColor { UIColor(red: red, green: green, blue: blue, alpha: 1) }
    var swiftUIColor: Color { Color(red: red, green: green, blue: blue) }
    static let cyan = RGBAColor(red: 0.25, green: 0.91, blue: 1)
    static let gold = RGBAColor(red: 1, green: 0.76, blue: 0.31)
    static let violet = RGBAColor(red: 0.72, green: 0.42, blue: 1)
}

enum MotionStyle: String, Codable, CaseIterable, Identifiable {
    case cyberMatrix = "Cyber Matrix", goldenParticles = "Golden Particles", neonLight = "Neon Light"
    case magicRune = "Magic Rune", smokeReveal = "Smoke Reveal", glassAssemble = "Glass Assemble"
    case liquidInk = "Liquid Ink", cosmicSpace = "Cosmic Space", kineticType = "Kinetic Typography"
    case laserScan = "Laser Scan", metallic3D = "3D Metallic", paperFold = "Paper Fold"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .cyberMatrix: "cpu"; case .goldenParticles: "sparkles"; case .neonLight: "bolt";
        case .magicRune: "moon.stars"; case .smokeReveal: "cloud.fog"; case .glassAssemble: "square.stack.3d.up"
        case .liquidInk: "drop"; case .cosmicSpace: "moonphase.waning.gibbous"; case .kineticType: "waveform"
        case .laserScan: "line.diagonal"; case .metallic3D: "cube.transparent"; case .paperFold: "doc"
        }
    }
    var category: String {
        switch self {
        case .cyberMatrix, .laserScan: "Futuristic"
        case .goldenParticles, .magicRune: "Fantasy"
        case .neonLight, .kineticType: "Kinetic"
        case .smokeReveal, .glassAssemble, .liquidInk, .paperFold: "Abstract"
        case .cosmicSpace: "Cinematic"
        case .metallic3D: "3D"
        }
    }
    var accent: RGBAColor {
        switch self {
        case .goldenParticles, .metallic3D, .paperFold: .gold
        case .magicRune, .cosmicSpace, .smokeReveal: .violet
        default: .cyan
        }
    }
}

enum TextMotion: String, Codable, CaseIterable, Identifiable {
    case pages = "Theo từng câu"
    case reveal = "Hiện chữ dần"
    case scrollUp = "Chạy từ dưới lên"
    var id: String { rawValue }
}
struct CaptionCue: Codable, Equatable {
    var text: String
    var startTime: Double
    var endTime: Double
}

/// Shared segmentation for the speech engine and video renderer. Punctuation
/// stays in the spoken text; chunks are kept short for portrait video.
enum CaptionSegmenter {
    static func split(_ text: String) -> [String] {
        let separators = CharacterSet(charactersIn: ".!?;:\n")
        var sentences: [String] = []
        var current = ""
        for character in text {
            current.append(character)
            if character.unicodeScalars.allSatisfy({ separators.contains($0) }) {
                let line = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !line.isEmpty { sentences.append(line) }
                current = ""
            }
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { sentences.append(tail) }
        var result: [String] = []
        for sentence in sentences {
            var chunk = ""
            var wordCount = 0
            for word in sentence.split(whereSeparator: { $0.isWhitespace }) {
                let value = String(word)
                if !chunk.isEmpty && (chunk.count + value.count + 1 > 68 || wordCount >= 11) {
                    result.append(chunk)
                    chunk = value
                    wordCount = 1
                } else {
                    chunk = chunk.isEmpty ? value : chunk + " " + value
                    wordCount += 1
                }
            }
            if !chunk.isEmpty { result.append(chunk) }
        }
        return result
    }
}

enum VoiceStyle: String, Codable, CaseIterable, Identifiable {
    case natural = "Tự nhiên"
    case warm = "Trầm ấm"
    case gentle = "Dịu dàng"
    case energetic = "Năng động"
    case storyteller = "Kể chuyện"
    case custom = "Tùy chỉnh"
    var id: String { rawValue }
    var settings: (rate: Float, pitch: Float, volume: Float) {
        switch self {
        case .natural: (0.50, 1.00, 1.0)
        case .warm: (0.46, 0.82, 1.0)
        case .gentle: (0.45, 1.12, 0.86)
        case .energetic: (0.57, 1.17, 1.0)
        case .storyteller: (0.47, 0.94, 0.95)
        case .custom: (0.50, 1.00, 1.0)
        }
    }
}

struct VoiceConfiguration: Codable, Equatable {
    var voiceIdentifier = ""
    var style: VoiceStyle = .natural
    var rate: Float = 0.50
    var pitch: Float = 1.00
    var volume: Float = 1.00

    mutating func apply(_ preset: VoiceStyle) {
        style = preset
        if preset != .custom {
            let value = preset.settings
            rate = value.rate
            pitch = value.pitch
            volume = value.volume
        }
    }
}

struct TextScene: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var text: String
    var duration: Double = 8
    var style: MotionStyle = .cyberMatrix
    var seed: UInt64 = UInt64.random(in: 1...UInt64.max)
    var noiseCount: Int = 70
    var foreground: RGBAColor = .cyan
    var title: String = "Cảnh 1"
    var transitionDuration: Double = 0.4
    var textMotion: TextMotion = .pages
    var scrollSpeed: Double = 1.0
    var captionCues: [CaptionCue] = []
    var voiceConfiguration: VoiceConfiguration = VoiceConfiguration()
    enum CodingKeys: String, CodingKey {
        case id, text, duration, style, seed, noiseCount, foreground, title, transitionDuration, textMotion, scrollSpeed, captionCues, voiceConfiguration
    }
    init(id: UUID = UUID(), text: String, duration: Double = 8, style: MotionStyle = .cyberMatrix,
         seed: UInt64 = UInt64.random(in: 1...UInt64.max), noiseCount: Int = 70,
         foreground: RGBAColor = .cyan, title: String = "Cảnh 1",
         transitionDuration: Double = 0.4, textMotion: TextMotion = .pages, scrollSpeed: Double = 1.0,
         captionCues: [CaptionCue] = [], voiceConfiguration: VoiceConfiguration = VoiceConfiguration()) {
        self.id = id; self.text = text; self.duration = duration; self.style = style
        self.seed = seed; self.noiseCount = noiseCount; self.foreground = foreground
        self.title = title; self.transitionDuration = transitionDuration
        self.textMotion = textMotion; self.scrollSpeed = scrollSpeed; self.captionCues = captionCues
        self.voiceConfiguration = voiceConfiguration
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        text = try c.decode(String.self, forKey: .text)
        duration = try c.decode(Double.self, forKey: .duration)
        style = try c.decode(MotionStyle.self, forKey: .style)
        seed = try c.decode(UInt64.self, forKey: .seed)
        noiseCount = try c.decode(Int.self, forKey: .noiseCount)
        foreground = try c.decode(RGBAColor.self, forKey: .foreground)
        title = try c.decode(String.self, forKey: .title)
        transitionDuration = try c.decodeIfPresent(Double.self, forKey: .transitionDuration) ?? 0.4
        textMotion = try c.decodeIfPresent(TextMotion.self, forKey: .textMotion) ?? .pages
        scrollSpeed = try c.decodeIfPresent(Double.self, forKey: .scrollSpeed) ?? 1.0
        captionCues = try c.decodeIfPresent([CaptionCue].self, forKey: .captionCues) ?? []
        voiceConfiguration = try c.decodeIfPresent(VoiceConfiguration.self, forKey: .voiceConfiguration) ?? VoiceConfiguration()
    }
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.text == rhs.text && lhs.duration == rhs.duration
        && lhs.style == rhs.style && lhs.seed == rhs.seed && lhs.noiseCount == rhs.noiseCount
        && lhs.foreground == rhs.foreground && lhs.title == rhs.title
        && lhs.transitionDuration == rhs.transitionDuration && lhs.textMotion == rhs.textMotion
        && lhs.scrollSpeed == rhs.scrollSpeed && lhs.captionCues == rhs.captionCues
        && lhs.voiceConfiguration == rhs.voiceConfiguration
    }
}

struct AudioClip: Codable, Identifiable, Equatable {
    var id = UUID()
    var relativeFilename: String
    var displayName: String
    var startTime: Double = 0
    var sourceIn: Double = 0
    var duration: Double = 0
    var volume: Float = 0.85
    var fadeIn: Double = 0.5
    var fadeOut: Double = 0.5
}

struct StudioProject: Codable {
    var id = UUID()
    var name = "ViePN Reveal Project"
    var scenes: [TextScene] = [TextScene(text: "", title: "Cảnh 1")]
    var audioClips: [AudioClip] = []
    var aspect: VideoAspect = .portrait
    var fps: Int = 30
    var width: Int = 720
    var createdAt = Date()
    var totalDuration: Double { scenes.reduce(0) { $0 + $1.duration } }
}

enum VideoAspect: String, Codable, CaseIterable, Identifiable {
    case portrait = "9:16", landscape = "16:9", square = "1:1", social = "4:5"
    var id: String { rawValue }
    func size(for width: Int) -> CGSize {
        let h: Int
        switch self { case .portrait: h = Int(Double(width) * 16 / 9); case .landscape: h = Int(Double(width) * 9 / 16); case .square: h = width; case .social: h = Int(Double(width) * 5 / 4) }
        return CGSize(width: width, height: h + (h % 2))
    }
}
