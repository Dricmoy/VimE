import AppKit
import VimECore

/// One transparent, click-through, non-activating panel per screen, so the target app keeps focus.
final class Overlay {
    private var panels: [NSPanel] = []
    private var views: [HintView] = []

    /// `frames` are in accessibility space, parallel to `labels`.
    func show(labels: [String], frames: [CGRect]) {
        hide()
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        for screen in NSScreen.screens {
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

            let view = HintView(frame: NSRect(origin: .zero, size: screen.frame.size))
            for (i, frame) in frames.enumerated() {
                let cocoa = Geometry.cocoaRect(fromAX: frame, primaryHeight: primaryHeight)
                guard cocoa.intersects(screen.frame) else { continue }
                view.hints.append((i, labels[i], cocoa.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)))
            }
            panel.contentView = view
            panel.orderFrontRegardless()
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
    var hints: [(index: Int, label: String, rect: NSRect)] = []
    var typed = ""

    private let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .bold)

    override func draw(_ dirtyRect: NSRect) {
        for hint in hints where hint.label.hasPrefix(typed) {
            let done = NSAttributedString(string: typed.uppercased(),
                                          attributes: [.font: font, .foregroundColor: NSColor(white: 0.45, alpha: 1)])
            let rest = NSAttributedString(string: String(hint.label.dropFirst(typed.count)).uppercased(),
                                          attributes: [.font: font, .foregroundColor: NSColor.black])
            let text = NSMutableAttributedString(attributedString: done)
            text.append(rest)

            let size = text.size()
            var badge = NSRect(x: hint.rect.minX, y: hint.rect.maxY - size.height - 2,
                               width: size.width + 6, height: size.height + 2)
            // Keep badges on screen for elements touching the edges.
            badge.origin.x = min(max(badge.minX, 0), bounds.maxX - badge.width)
            badge.origin.y = min(max(badge.minY, 0), bounds.maxY - badge.height)

            NSColor(calibratedRed: 1, green: 0.85, blue: 0.2, alpha: 1).setFill()
            NSBezierPath(roundedRect: badge, xRadius: 3, yRadius: 3).fill()
            NSColor(white: 0, alpha: 0.35).setStroke()
            NSBezierPath(roundedRect: badge, xRadius: 3, yRadius: 3).stroke()
            text.draw(at: NSPoint(x: badge.minX + 3, y: badge.minY + 1))
        }
    }
}
