import UIKit

/// One renderer is shared by live preview and file export to ensure matching timing.
final class FrameRenderer {
    static let shared = FrameRenderer()
    private let cacheLock = NSLock()
    private var cachedKey = ""
    private var cachedValue: ScrambledText?
    private func scramble(for scene: TextScene) -> ScrambledText {
        let key = String(describing: scene.id) + "|" + String(scene.seed) + "|" + String(scene.noiseCount) + "|" + scene.text
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if cachedKey == key, let cachedValue { return cachedValue }
        let value = ScrambleEngine.generate(text: scene.text, noiseCount: scene.noiseCount, seed: scene.seed)
        cachedKey = key
        cachedValue = value
        return value
    }
    func render(scene: TextScene, time: Double, size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            let ctx = renderer.cgContext
            let W = size.width, H = size.height
            UIColor(red: 0.025, green: 0.038, blue: 0.085, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let progress = CGFloat(min(1, max(0, time / max(scene.duration * 0.83, 0.01))))
            let accent = scene.style.accent.uiColor
            var rng = SeededGenerator(seed: scene.seed)
            let scrambled = scramble(for: scene)

            // Subtle star/dust field, with style-specific visual treatments.
            for _ in 0..<55 {
                let x = CGFloat(Int.random(in: 0..<max(1, Int(W)), using: &rng))
                let y = CGFloat(Int.random(in: 0..<max(1, Int(H)), using: &rng))
                let radius = CGFloat(Int.random(in: 1...3, using: &rng)) * W / 720
                let twinkle = 0.16 + 0.26 * abs(sin(Double(x + y) * 0.01 + time * 1.3))
                ctx.setFillColor(accent.withAlphaComponent(twinkle).cgColor)
                ctx.fillEllipse(in: CGRect(x: x, y: y, width: radius, height: radius))
            }
            if scene.style == .cyberMatrix || scene.style == .laserScan {
                ctx.setStrokeColor(accent.withAlphaComponent(0.12).cgColor)
                ctx.setLineWidth(1)
                let step = max(W / 17, 12)
                stride(from: CGFloat(0), through: W, by: step).forEach { x in ctx.move(to: CGPoint(x: x, y: 0)); ctx.addLine(to: CGPoint(x: x, y: H)) }
                ctx.strokePath()
            }

            let headerSize = max(12, W * 0.024)
            drawText("SECRET TEXT   /   \(scene.style.rawValue.uppercased())", in: CGRect(x: W * 0.07, y: H * 0.085, width: W * 0.86, height: 44), font: .monospacedSystemFont(ofSize: headerSize, weight: .medium), color: accent.withAlphaComponent(0.75), alignment: .left)

            let cols = max(12, Int(W / max(12, W * 0.036)))
            let glyph = max(11, W * 0.027)
            let cellW = W * 0.88 / CGFloat(cols)
            let cellH = glyph * 1.55
            let startX = W * 0.06
            let gridY = H * 0.23
            let revealed = Int(Double(scrambled.messageCharacters.count) * Double(progress))
            let litPositions = Set(scrambled.sourceIndices.prefix(revealed))
            for (index, letter) in scrambled.visible.prefix(180).enumerated() {
                let row = index / cols, col = index % cols
                let x = startX + CGFloat(col) * cellW
                let y = gridY + CGFloat(row) * cellH
                guard y < H * 0.64 else { break }
                let active = litPositions.contains(index)
                let alpha: CGFloat = active ? 1 : (scene.style == .smokeReveal ? 0.12 + (1-progress) * 0.25 : 0.17)
                let color = active ? accent : UIColor.white
                if active {
                    ctx.saveGState(); ctx.setShadow(offset: .zero, blur: glyph * 0.6, color: accent.cgColor)
                }
                let offset = active ? CGFloat(sin(time * 4 + Double(index))) * 2 : 0
                drawText(letter, in: CGRect(x: x, y: y - offset, width: cellW + 2, height: cellH), font: .monospacedSystemFont(ofSize: glyph, weight: active ? .bold : .regular), color: color.withAlphaComponent(alpha), alignment: .center)
                if active { ctx.restoreGState() }
            }

            switch scene.style {
            case .cyberMatrix:
                drawScanline(ctx: ctx, y: H * (0.20 + 0.47 * progress), width: W, accent: accent)
            case .laserScan:
                drawScanline(ctx: ctx, y: H * (0.70 - 0.45 * progress), width: W, accent: accent)
            case .goldenParticles, .cosmicSpace, .magicRune:
                let count = scene.style == .goldenParticles ? 130 : 65
                for i in 0..<count {
                    let angle = Double(i) * 2.39996 + time * (scene.style == .magicRune ? 0.8 : 0.22)
                    let radius = CGFloat(40 + (i % 80) * 3) * (1 - 0.42 * progress) * W / 720
                    let x = W/2 + CGFloat(cos(angle)) * radius
                    let y = H*0.77 + CGFloat(sin(angle)) * radius * 0.42
                    ctx.setFillColor(accent.withAlphaComponent(0.05 + progress * 0.5).cgColor)
                    ctx.fillEllipse(in: CGRect(x: x, y: y, width: 2.6 * W/720, height: 2.6 * W/720))
                }
            case .neonLight:
                let rect = CGRect(x: W * 0.055, y: H * 0.69, width: W * 0.89, height: H * 0.16)
                ctx.setStrokeColor(accent.withAlphaComponent(0.5 * progress).cgColor)
                ctx.setLineWidth(W * 0.003)
                ctx.stroke(rect)
            case .glassAssemble, .paperFold, .metallic3D:
                for i in 0..<12 {
                    let x = W * CGFloat((i * 71) % 100) / 100
                    let y = H * (0.72 + CGFloat((i * 13) % 20) / 100)
                    ctx.setStrokeColor(accent.withAlphaComponent(0.4 * (1-progress)).cgColor)
                    ctx.stroke(CGRect(x: x + (1-progress)*W*0.08, y: y, width: W*0.045, height: H*0.024))
                }
            case .liquidInk, .smokeReveal:
                let blurRadius = W * (1-progress) * 0.2
                ctx.setFillColor(accent.withAlphaComponent(0.03 + 0.09 * progress).cgColor)
                ctx.fillEllipse(in: CGRect(x: W/2 - blurRadius*2, y: H*0.76 - blurRadius, width: blurRadius*4, height: blurRadius*2))
            case .kineticType:
                let baseline = H * 0.89
                for i in 0..<44 {
                    let h = CGFloat(abs(sin(time * 3 + Double(i) * 0.6))) * H * 0.028
                    ctx.setFillColor(accent.withAlphaComponent(0.4).cgColor)
                    ctx.fill(CGRect(x: CGFloat(i)*W/44, y: baseline-h, width: W/90, height: h))
                }
            }

            let msgFont = UIFont.systemFont(ofSize: max(24, W * 0.061), weight: .bold)
            if scene.textMotion == .scrollUp {
                drawScroll(scene: scene, in: ctx, width: W, height: H,
                           time: time, font: msgFont,
                           color: scene.style == .paperFold ? .white : accent)
            } else {
                let message = scrambled.messageCharacters.prefix(revealed).joined()
                let finalText = message.isEmpty ? "· · ·" : message
                let move: CGFloat = (1 - progress) * (scene.style == .kineticType ? 95 : 32) * W / 720
                let textRect = CGRect(x: W * 0.07, y: H * 0.69 + move, width: W * 0.86, height: H * 0.15)
                ctx.saveGState()
                ctx.setShadow(offset: .zero, blur: W * 0.01, color: accent.withAlphaComponent(0.7).cgColor)
                drawText(finalText, in: textRect, font: msgFont,
                         color: scene.style == .paperFold ? .white : accent, alignment: .center)
                ctx.restoreGState()
            }
            let footer = String(format: "%02d%%   •   %@", Int(progress * 100), scene.title.uppercased())
            drawText(footer, in: CGRect(x: W*0.07, y: H*0.94, width: W*0.86, height: 28), font: .monospacedSystemFont(ofSize: max(10, W*0.021), weight: .light), color: .white.withAlphaComponent(0.42), alignment: .center)
        }
    }

    private func drawScroll(scene: TextScene, in ctx: CGContext, width: CGFloat,
                            height: CGFloat, time: Double, font: UIFont, color: UIColor) {
        let viewport = CGRect(x: width * 0.065, y: height * 0.53,
                              width: width * 0.87, height: height * 0.38)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = font.pointSize * 0.25
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: color, .paragraphStyle: paragraph
        ]
        let text = scene.text.isEmpty ? "· · ·" : scene.text
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let maxWidth = viewport.width * 0.97
        let bounds = attributed.boundingRect(
            with: CGSize(width: maxWidth, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil
        )
        let textHeight = max(ceil(bounds.height) + font.lineHeight, font.lineHeight)
        let speed = max(0.25, min(3, scene.scrollSpeed))
        let fraction = CGFloat(min(1, max(0, time * speed / max(scene.duration, 0.1))))
        let initialY = viewport.maxY + font.lineHeight
        let finalY = viewport.minY - textHeight - font.lineHeight
        let y = initialY + (finalY - initialY) * fraction
        ctx.saveGState()
        ctx.clip(to: viewport)
        (text as NSString).draw(
            in: CGRect(x: viewport.minX + viewport.width * 0.015, y: y,
                       width: maxWidth, height: textHeight),
            withAttributes: attributes
        )
        ctx.restoreGState()
    }

    private func drawScanline(ctx: CGContext, y: CGFloat, width: CGFloat, accent: UIColor) {
        ctx.saveGState(); ctx.setShadow(offset: .zero, blur: width * 0.025, color: accent.cgColor)
        ctx.setStrokeColor(accent.withAlphaComponent(0.9).cgColor); ctx.setLineWidth(max(2, width * 0.004))
        ctx.move(to: CGPoint(x: width*0.055, y: y)); ctx.addLine(to: CGPoint(x: width*0.945, y: y)); ctx.strokePath(); ctx.restoreGState()
    }
    private func drawText(_ value: String, in rect: CGRect, font: UIFont, color: UIColor, alignment: NSTextAlignment) {
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = alignment
        paragraph.lineBreakMode = .byWordWrapping
        (value as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
    }
}
