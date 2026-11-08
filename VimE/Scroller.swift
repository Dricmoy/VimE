import AppKit
import VimECore

/// Scrolls the frontmost app's main content with synthetic scroll-wheel events.
final class Scroller {
    private let queue = DispatchQueue(label: "VimE.scroll", qos: .userInteractive)
    /// Queue-only. Finding the scroll area walks the tree, so reuse it while a key is held.
    private var cached: (pid: pid_t, rect: CGRect, at: TimeInterval)?

    func scroll(_ command: ScrollCommand, pid: pid_t, isRepeat: Bool) {
        queue.async { [self] in
            guard let rect = scrollRect(pid: pid) else { return }
            let d = command.delta(viewport: rect.size)
            // Held keys repeat ~30 times a second, so one event each keeps up; single presses animate.
            let toEnd = abs(d.dy) >= ScrollCommand.toEnd
            let count = max(toEnd || isRepeat ? 1 : 5, ScrollCommand.minimumSteps(dx: d.dx, dy: d.dy))
            let point = CGPoint(x: rect.midX, y: rect.midY)
            for (i, step) in ScrollCommand.steps(dx: d.dx, dy: d.dy, count: count).enumerated() {
                // Spaced out so the window server doesn't merge them back into one oversized event.
                if i > 0 { usleep(toEnd ? 5_000 : 8_000) }
                post(dx: step.dx, dy: step.dy, at: point)
            }
        }
    }

    func invalidate() {
        queue.async { [self] in cached = nil }
    }

    private func scrollRect(pid: pid_t) -> CGRect? {
        let now = ProcessInfo.processInfo.systemUptime
        if let cached, cached.pid == pid, now - cached.at < 3 { return cached.rect }
        guard let rect = Accessibility.scrollRect(pid: pid) else { return nil }
        cached = (pid, rect, now)
        return rect
    }

    /// Posted into the session stream at `point` (accessibility space); the window server
    /// delivers it to whatever is under that point. Sending straight to the app's pid doesn't scroll.
    private func post(dx: Int32, dy: Int32, at point: CGPoint) {
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                                  wheel1: dy, wheel2: dx, wheel3: 0) else { return }
        event.location = point
        event.post(tap: .cgSessionEventTap)
    }
}
