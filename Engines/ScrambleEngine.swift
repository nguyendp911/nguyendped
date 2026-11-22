import Foundation

/// Stores the source mapping, rather than attempting to recover the message from the noise.
struct ScrambledText {
    let visible: [String]
    let sourceIndices: [Int]
    let messageCharacters: [String]
    var obscured: String { visible.joined() }
}

struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

enum ScrambleEngine {
    private static let alphabet: [String] = Array("ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789@#%&*+?∞◇△").map(String.init)

    static func generate(text: String, noiseCount: Int, seed: UInt64) -> ScrambledText {
        // Swift Character iteration preserves extended grapheme clusters such as Vietnamese vowels.
        let message = text.map { String($0) }
        guard !message.isEmpty else { return ScrambledText(visible: [], sourceIndices: [], messageCharacters: []) }
        var rng = SeededGenerator(seed: seed)
        let noise = min(max(noiseCount, 0), 500)
        let count = message.count + noise
        var positions = Array(0..<count)
        positions.shuffle(using: &rng)
        positions = Array(positions.prefix(message.count)).sorted()
        var result: [String] = []
        var mapping: [Int] = []
        var next = 0
        for i in 0..<count {
            if next < positions.count && positions[next] == i {
                result.append(message[next]); mapping.append(i); next += 1
            } else {
                result.append(alphabet[Int.random(in: 0..<alphabet.count, using: &rng)])
            }
        }
        return ScrambledText(visible: result, sourceIndices: mapping, messageCharacters: message)
    }
}
