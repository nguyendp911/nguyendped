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
    enum CodingKeys: String, CodingKey {
        case id, text, duration, style, seed, noiseCount, foreground, title, transitionDuration, textMotion, scrollSpeed
    }
    init(id: UUID = UUID(), text: String, duration: Double = 8, style: MotionStyle = .cyberMatrix,
         seed: UInt64 = UInt64.random(in: 1...UInt64.max), noiseCount: Int = 70,
         foreground: RGBAColor = .cyan, title: String = "Cảnh 1",
         transitionDuration: Double = 0.4, textMotion: TextMotion = .pages, scrollSpeed: Double = 1.0) {
        self.id = id; self.text = text; self.duration = duration; self.style = style
        self.seed = seed; self.noiseCount = noiseCount; self.foreground = foreground
        self.title = title; self.transitionDuration = transitionDuration
        self.textMotion = textMotion; self.scrollSpeed = scrollSpeed
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
    }
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.text == rhs.text && lhs.duration == rhs.duration
        && lhs.style == rhs.style && lhs.seed == rhs.seed && lhs.noiseCount == rhs.noiseCount
        && lhs.foreground == rhs.foreground && lhs.title == rhs.title
        && lhs.transitionDuration == rhs.transitionDuration && lhs.textMotion == rhs.textMotion
        && lhs.scrollSpeed == rhs.scrollSpeed
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
    var name = "Secret Text Project"
    var scenes: [TextScene] = [TextScene(text: "Anh yêu em mãi mãi", title: "Lời nhắn đầu tiên")]
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
