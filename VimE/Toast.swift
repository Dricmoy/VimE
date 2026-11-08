import AppKit
import SwiftUI

private struct ToastView: View {
    let title: String
    let detail: String?

    var body: some View {
        VStack(spacing: 2) {
            Text(title).font(.system(size: 15, weight: .semibold))
            if let detail { Text(detail).font(.system(size: 12)).foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

/// A short message near the bottom of the screen the pointer is on, e.g. after the on/off shortcut.
/// Never takes focus or clicks.
final class Toast {
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    func show(_ title: String, detail: String? = nil, seconds: TimeInterval = 1.4) {
        hideWork?.cancel()
        panel?.orderOut(nil)

        let host = NSHostingView(rootView: ToastView(title: title, detail: detail))
        let size = host.fittingSize
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let area = screen?.visibleFrame ?? .zero
        let panel = NSPanel(contentRect: NSRect(x: area.midX - size.width / 2, y: area.minY + area.height * 0.12,
                                                width: size.width, height: size.height),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = host
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.orderFrontRegardless()
        self.panel = panel

        let work = DispatchWorkItem { [weak self, weak panel] in
            guard let panel else { return }
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; panel.animator().alphaValue = 0 }) {
                panel.orderOut(nil)
                if self?.panel === panel { self?.panel = nil }
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }
}
