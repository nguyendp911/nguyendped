import AppKit
import Foundation

// Generates a 1024px iOS App Icon for ViePN tenungdung at build time.
// No external image editor or network dependency.
let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("App/Assets.xcassets/AppIcon.appiconset/Icon.png")
try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)

let size = 1024
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: size,
    pixelsHigh: size,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fatalError("Cannot create icon bitmap")
}
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
let rect = NSRect(x: 0, y: 0, width: size, height: size)
NSGradient(starting: NSColor(calibratedRed: 0.01, green: 0.10, blue: 0.22, alpha: 1),
           ending: NSColor(calibratedRed: 0.075, green: 0.015, blue: 0.17, alpha: 1))!
    .draw(in: rect, angle: -35)
let cyan = NSColor(calibratedRed: 0.20, green: 0.90, blue: 1.0, alpha: 1)
let purple = NSColor(calibratedRed: 0.75, green: 0.35, blue: 1.0, alpha: 1)
let gold = NSColor(calibratedRed: 1.0, green: 0.71, blue: 0.36, alpha: 1)

let ring = NSBezierPath(ovalIn: NSRect(x: 155, y: 160, width: 714, height: 714))
ring.lineWidth = 19
cyan.withAlphaComponent(0.85).setStroke()
ring.stroke()
let inner = NSBezierPath(ovalIn: NSRect(x: 199, y: 204, width: 626, height: 626))
inner.lineWidth = 7
purple.withAlphaComponent(0.78).setStroke()
inner.stroke()

// Film-like edge marks around the motion ring.
for i in 0..<20 {
    let a = CGFloat(i) * CGFloat.pi / 10
    let center = NSPoint(x: 512 + cos(a) * 363, y: 512 + sin(a) * 363)
    let dot = NSBezierPath(ovalIn: NSRect(x: center.x-8, y: center.y-8, width: 16, height: 16))
    (i.isMultiple(of: 3) ? gold : cyan).withAlphaComponent(0.92).setFill()
    dot.fill()
}

// Center play symbol with a luminous perimeter.
let triangle = NSBezierPath()
triangle.move(to: NSPoint(x: 420, y: 565))
triangle.line(to: NSPoint(x: 420, y: 752))
triangle.line(to: NSPoint(x: 598, y: 658))
triangle.close()
NSGradient(starting: cyan, ending: purple)!.draw(in: triangle, angle: -20)

let style = NSMutableParagraphStyle()
style.alignment = .center
func label(_ text: String, y: CGFloat, fontSize: CGFloat, weight: NSFont.Weight, color: NSColor) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: fontSize, weight: weight),
        .foregroundColor: color,
        .paragraphStyle: style
    ]
    let sizeOfText = (text as NSString).size(withAttributes: attributes)
    (text as NSString).draw(in: NSRect(x: 60, y: y, width: 904,
                                      height: max(110, sizeOfText.height+20)),
                            withAttributes: attributes)
}
label("ViePN", y: 385, fontSize: 150, weight: .heavy, color: .white)
label("tenungdung", y: 299, fontSize: 58, weight: .medium, color: cyan)

for i in 0..<29 {
    let t = CGFloat(i) / 28
    let height = CGFloat(25 + 67 * abs(sin(t * .pi * 5)))
    let r = NSRect(x: 265 + CGFloat(i)*17, y: 250-height/2, width: 9, height: height)
    (i.isMultiple(of: 2) ? cyan : purple).setFill()
    NSBezierPath(roundedRect: r, xRadius: 4, yRadius: 4).fill()
}
context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()
guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Cannot encode PNG") }
try png.write(to: output, options: .atomic)
print("Generated icon: \\(output.path)")
