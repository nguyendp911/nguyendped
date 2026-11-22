// Run independently on macOS or Linux:
// swiftc Engines/ScrambleEngine.swift Tests/ScrambleSmokeTest.swift -o /tmp/scramble-smoke && /tmp/scramble-smoke
import Foundation

@main struct ScrambleSmokeTest {
    static func main() {
        let cases = ["anh yêu em mãi mãi", "Tiếng Việt 🇻🇳", "e\u{301}👨‍👩‍👧‍👦", "xin chào 123", "a b c"]
        for message in cases {
            let a = ScrambleEngine.generate(text: message, noiseCount: 85, seed: 12345)
            let b = ScrambleEngine.generate(text: message, noiseCount: 85, seed: 12345)
            precondition(a.visible == b.visible)
            precondition(a.sourceIndices.count == message.count)
            precondition(a.sourceIndices == a.sourceIndices.sorted())
            let recovered = a.sourceIndices.map { a.visible[$0] }.joined()
            precondition(recovered == message, "Unicode roundtrip failed")
            print("PASS: \(message)")
        }
    }
}
