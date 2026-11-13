import AppKit
import VimECore

/// Colours for one badge style.
struct BadgeTheme {
    var fill: NSColor
    var text: NSColor
    var border: NSColor
    var shadow: NSColor

    static func resolve(_ style: BadgeStyle) -> BadgeTheme {
        switch style {
        case .auto:
            let dark = NSApplication.shared.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return resolve(dark ? .light : .dark)
        case .dark:
            return BadgeTheme(fill: NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 0.95), text: .white,
                              border: NSColor(white: 1, alpha: 0.22), shadow: NSColor(white: 0, alpha: 0.35))
        case .light:
            return BadgeTheme(fill: NSColor(srgbRed: 0.97, green: 0.97, blue: 0.98, alpha: 0.97),
                              text: NSColor(white: 0.07, alpha: 1),
                              border: NSColor(white: 0, alpha: 0.2), shadow: NSColor(white: 0, alpha: 0.3))
        case .classic:
            return BadgeTheme(fill: NSColor(srgbRed: 1, green: 0.85, blue: 0.2, alpha: 1), text: .black,
                              border: NSColor(white: 0, alpha: 0.35), shadow: NSColor(white: 0, alpha: 0.25))
        }
    }
}

/// One transparent, click-through, non-activating panel per screen, so the target app keeps focus.
final class Overlay {
    private var panels: [NSPanel] = []
    private var views: [HintView] = []

    /// `frames` are in accessibility space, parallel to `labels`.
    func show(labels: [String], frames: [CGRect], style: BadgeStyle, size: BadgeSize) {
        hide()
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let theme = BadgeTheme.resolve(style)
        let font = NSFont.monospacedSystemFont(ofSize: size.fontSize, weight: .bold)
        for screen in NSScreen.screens {
            // Accessibility space is top-left based like the flipped view, so only the origin moves.
            let screenAX = Geometry.axRect(fromCocoa: screen.frame, primaryHeight: primaryHeight)
            let local = CGRect(origin: .zero, size: screen.frame.size)
            var entries: [(label: String, element: CGRect)] = []
            for (i, frame) in frames.enumerated() where frame.intersects(screenAX) {
                entries.append((labels[i], frame.offsetBy(dx: -screenAX.minX, dy: -screenAX.minY)))
            }
            guard !entries.isEmpty else { continue }

            let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            panel.setFrame(screen.frame, display: false)
            panel.level = .screenSaver
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

            let view = HintView.make(entries, in: local, theme: theme, font: font)
            panel.contentView = view
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.08
                panel.animator().alphaValue = 1
            }
            panels.append(panel)
            views.append(view)
        }
    }

    func update(typed: String) {
        for view in views {
            view.typed = typed
            view.needsDisplay = true
        }
    }

    func hide() {
        panels.forEach { $0.orderOut(nil) }
        panels = []
        views = []
    }
}

private final class HintView: NSView {
    var hints: [(label: String, badge: CGRect)] = []
    var typed = ""
    var theme = BadgeTheme.resolve(.dark)
    var font = NSFont.monospacedSystemFont(ofSize: BadgeSize.medium.fontSize, weight: .bold)

    static let padding = CGSize(width: 4, height: 1.5)
    static let tracking: CGFloat = 0.6

    override var isFlipped: Bool { true }

    /// `elements` are in the view's own top-left coordinates.
    static func make(_ entries: [(label: String, element: CGRect)], in bounds: CGRect, theme: BadgeTheme,
                     font: NSFont) -> HintView {
        let anchors = entries.map { BadgeLayout.anchor(element: $0.element, size: badgeSize($0.label, font: font)) }
        let placed = BadgeLayout.place(anchors, in: bounds.insetBy(dx: 2, dy: 2))
        let view = HintView(frame: bounds)
        view.theme = theme
        view.font = font
        view.hints = zip(entries, placed).map { ($0.label, $1) }
        return view
    }

    static func badgeSize(_ label: String, font: NSFont) -> CGSize {
        let text = NSAttributedString(string: label.uppercased(), attributes: [.font: font, .kern: tracking])
        let size = text.size()
        return CGSize(width: ceil(size.width + padding.width * 2), height: ceil(size.height + padding.height * 2))
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius = round(font.pointSize * 0.42)
        let shadow = NSShadow()
        shadow.shadowColor = theme.shadow
        shadow.shadowBlurRadius = 3
        shadow.shadowOffset = NSSize(width: 0, height: -1)

        for hint in hints where hint.label.hasPrefix(typed) && hint.badge.intersects(dirtyRect) {
            let path = NSBezierPath(roundedRect: hint.badge.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
            NSGraphicsContext.saveGraphicsState()
            shadow.set()
            theme.fill.setFill()
            path.fill()
            NSGraphicsContext.restoreGraphicsState()
            theme.border.setStroke()
            path.lineWidth = 1
            path.stroke()

            // Letters already typed fade back, so the eye goes to what's left to type.
            let text = NSMutableAttributedString(string: typed.uppercased(), attributes: [
                .font: font, .kern: Self.tracking, .foregroundColor: theme.text.withAlphaComponent(0.4),
            ])
            text.append(NSAttributedString(string: String(hint.label.dropFirst(typed.count)).uppercased(), attributes: [
                .font: font, .kern: Self.tracking, .foregroundColor: theme.text,
            ]))
            text.draw(at: NSPoint(x: hint.badge.minX + Self.padding.width, y: hint.badge.minY + Self.padding.height))
        }
    }
}

#if DEBUG
extension Overlay {
    /// Draws real badges over a window screenshot, for checking the look without showing hints on screen.
    /// `elements` are relative to the screenshot's top-left, in points.
    static func render(over shot: NSImage, elements: [CGRect], labels: [String], style: BadgeStyle, size: BadgeSize,
                       typed: String = "") -> NSBitmapImageRep? {
        let bounds = CGRect(origin: .zero, size: shot.size)
        let container = NSView(frame: bounds)
        let image = NSImageView(frame: bounds)
        image.image = shot
        image.imageScaling = .scaleAxesIndependently
        container.addSubview(image)
        let font = NSFont.monospacedSystemFont(ofSize: size.fontSize, weight: .bold)
        let view = HintView.make(Array(zip(labels, elements)).map { ($0.0, $0.1) }, in: bounds,
                                 theme: BadgeTheme.resolve(style), font: font)
        view.typed = typed
        container.addSubview(view)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(bounds.width * 2),
                                         pixelsHigh: Int(bounds.height * 2), bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = bounds.size
        container.cacheDisplay(in: bounds, to: rep)
        return rep
    }
}
#endif
