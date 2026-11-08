// Draws VimE's app icon: a yellow hint label on a dark tile, the thing you see when you press f.
// Usage: swift scripts/make-icon.swift <out.iconset>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])

func draw(size: CGFloat) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = size / 1024  // design on a 1024 grid

    // Tile: macOS icon grid, 824 body with a continuous-looking corner.
    let tile = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185 * s, yRadius: 185 * s)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 24 * s
    shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor.black.setFill()
    tilePath.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: NSColor(calibratedRed: 0.20, green: 0.22, blue: 0.27, alpha: 1),
               ending: NSColor(calibratedRed: 0.07, green: 0.08, blue: 0.10, alpha: 1))!
        .draw(in: tilePath, angle: -90)
    NSColor.white.withAlphaComponent(0.08).setStroke()
    tilePath.lineWidth = 4 * s
    tilePath.stroke()

    // Faint UI lines the hints sit on.
    NSColor.white.withAlphaComponent(0.07).setFill()
    for (i, width) in [520.0, 400, 460, 300].enumerated() {
        NSBezierPath(roundedRect: NSRect(x: 220 * s, y: (330 - CGFloat(i) * 62) * s, width: width * s, height: 26 * s),
                     xRadius: 13 * s, yRadius: 13 * s).fill()
    }

    /// `origin.x` is the badge's center.
    func badge(_ text: String, at origin: NSPoint, height: CGFloat, alpha: CGFloat) {
        let font = NSFont.monospacedSystemFont(ofSize: height * 0.78, weight: .black)
        let label = NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: NSColor(calibratedWhite: 0.08, alpha: 1),
        ])
        let textSize = label.size()
        let width = textSize.width + height * 0.5
        let rect = NSRect(x: origin.x - width / 2, y: origin.y, width: width, height: height)
        let path = NSBezierPath(roundedRect: rect, xRadius: height * 0.18, yRadius: height * 0.18)
        NSGraphicsContext.saveGraphicsState()
        let glow = NSShadow()
        glow.shadowColor = NSColor.black.withAlphaComponent(0.45 * alpha)
        glow.shadowBlurRadius = height * 0.12
        glow.shadowOffset = NSSize(width: 0, height: -height * 0.05)
        glow.set()
        NSColor(calibratedRed: 1, green: 0.85, blue: 0.2, alpha: alpha).setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGradient(starting: NSColor(calibratedRed: 1, green: 0.90, blue: 0.38, alpha: alpha),
                   ending: NSColor(calibratedRed: 1, green: 0.78, blue: 0.10, alpha: alpha))!.draw(in: path, angle: -90)
        NSColor.black.withAlphaComponent(0.25 * alpha).setStroke()
        path.lineWidth = height * 0.03
        path.stroke()
        label.draw(at: NSPoint(x: rect.minX + (rect.width - textSize.width) / 2,
                               y: rect.minY + (height - textSize.height) / 2 + height * 0.02))
    }

    badge("JK", at: NSPoint(x: 680 * s, y: 250 * s), height: 120 * s, alpha: 0.55)
    badge("F", at: NSPoint(x: 512 * s, y: 450 * s), height: 320 * s, alpha: 1)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        try! draw(size: CGFloat(points * scale)).write(to: out.appendingPathComponent(name))
    }
}
