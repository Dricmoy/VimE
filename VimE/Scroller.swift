import AppKit
import VimECore

/// Scrolls the frontmost app's main content with synthetic scroll-wheel events, leaving the pointer
/// where it was. Scrolls are animated at display rate: a held j/k/h/l glides and speeds up until the
/// key is released, d/u ease through half a page, gg/G jump.
final class Scroller {
    private let queue = DispatchQueue(label: "VimE.scroll", qos: .userInteractive)
    /// Queue-only. Finding the scroll area walks the tree, so reuse it while a key is held.
    private var cached: (pid: pid_t, rect: CGRect, at: TimeInterval)?

    /// The scroll in progress. Queue-only.
    private struct Gesture {
        var motion: ScrollMotion
        /// Unit direction in Quartz convention (positive dy scrolls up, positive dx left).
        var unit: (dx: CGFloat, dy: CGFloat)
        /// The key whose release ends a held scroll.
        var keyCode: UInt16
        var aim: CGPoint
        /// Where the pointer was before the gesture, if the gesture had to move it.
        var restore: CGPoint?
        /// Fractions of a point not yet sent, so rounding never loses distance.
        var carry: (dx: CGFloat, dy: CGFloat) = (0, 0)
        var lastTick: TimeInterval
    }
    private var gesture: Gesture?
    private var timer: DispatchSourceTimer?
    private static let frame: TimeInterval = 1.0 / 120

    func scroll(_ command: ScrollCommand, pid: pid_t, isRepeat: Bool, keyCode: UInt16) {
        queue.async { [self] in
            switch command {
            case .top, .bottom:
                finish()
                jump(command, pid: pid)
            case .down, .up, .left, .right:
                // The first press already follows the key until release; repeats add nothing.
                if isRepeat, gesture?.keyCode == keyCode { return }
                start(.held(), command: command, pid: pid, keyCode: keyCode)
            case .halfPageDown, .halfPageUp:
                guard let rect = scrollRect(pid: pid) else { return }
                let distance = (rect.height / 2).rounded()
                start(.eased(distance: distance, duration: isRepeat ? 0.12 : 0.2), command: command, pid: pid,
                      keyCode: keyCode)
            }
        }
    }

    func invalidate() {
        queue.async { [self] in
            finish()
            cached = nil
        }
    }

    private func start(_ motion: ScrollMotion, command: ScrollCommand, pid: pid_t, keyCode: UInt16) {
        guard let rect = scrollRect(pid: pid) else { return }
        let d = command.delta(viewport: CGSize(width: 1, height: 1))
        let unit = (dx: d.dx == 0 ? 0 : d.dx / abs(d.dx), dy: d.dy == 0 ? 0 : d.dy / abs(d.dy))
        let now = ProcessInfo.processInfo.systemUptime
        if var current = gesture {
            // A new key mid-scroll takes over, keeping the aim and the pointer to restore.
            current.motion = motion
            current.unit = unit
            current.keyCode = keyCode
            current.carry = (0, 0)
            current.lastTick = now
            gesture = current
        } else {
            let pointer = Pointer.location
            let aim = ScrollCommand.aim(area: rect, pointer: pointer,
                                        pointerOverApp: Pointer.isOverApp(pid, at: pointer))
            gesture = Gesture(motion: motion, unit: unit, keyCode: keyCode, aim: aim.at,
                              restore: aim.restorePointer ? pointer : nil, lastTick: now)
        }
        if timer == nil {
            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now(), repeating: Self.frame, leeway: .milliseconds(1))
            t.setEventHandler { [weak self] in self?.tick() }
            t.resume()
            timer = t
        }
    }

    private func tick() {
        guard var g = gesture else { return finish() }
        let now = ProcessInfo.processInfo.systemUptime
        // Cap dt so a stalled frame doesn't turn into a jump.
        let dt = min(now - g.lastTick, 0.05)
        g.lastTick = now
        let held = CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(g.keyCode))
        let distance = g.motion.advance(dt: dt, held: held)
        let fx = g.unit.dx * distance + g.carry.dx, fy = g.unit.dy * distance + g.carry.dy
        let sx = fx.rounded(.towardZero), sy = fy.rounded(.towardZero)
        g.carry = (fx - sx, fy - sy)
        if sx != 0 || sy != 0 { post(dx: Int32(sx), dy: Int32(sy), at: g.aim) }
        gesture = g
        if g.motion.isFinished { finish() }
    }

    /// Stops any gesture and puts the pointer back if the gesture moved it.
    private func finish() {
        timer?.cancel()
        timer = nil
        if let restore = gesture?.restore { Pointer.restore(to: restore, tap: .cgSessionEventTap) }
        gesture = nil
    }

    /// gg / G: straight to the end, in a few large events.
    private func jump(_ command: ScrollCommand, pid: pid_t) {
        guard let rect = scrollRect(pid: pid) else { return }
        let d = command.delta(viewport: rect.size)
        let count = ScrollCommand.minimumSteps(dx: d.dx, dy: d.dy)
        let pointer = Pointer.location
        let aim = ScrollCommand.aim(area: rect, pointer: pointer, pointerOverApp: Pointer.isOverApp(pid, at: pointer))
        for (i, step) in ScrollCommand.steps(dx: d.dx, dy: d.dy, count: count).enumerated() {
            // Spaced out so the window server doesn't merge them back into one oversized event.
            if i > 0 { usleep(5_000) }
            post(dx: step.dx, dy: step.dy, at: aim.at)
        }
        if aim.restorePointer { Pointer.restore(to: pointer, tap: .cgSessionEventTap) }
    }

    private func scrollRect(pid: pid_t) -> CGRect? {
        let now = ProcessInfo.processInfo.systemUptime
        if let cached, cached.pid == pid, now - cached.at < 3 { return cached.rect }
        guard let rect = Accessibility.scrollRect(pid: pid) else { return nil }
        cached = (pid, rect, now)
        return rect
    }

    /// Posted into the session stream at `point` (accessibility space); the window server
    /// delivers it to whatever is under that point, moving the pointer there. Sending straight to the
    /// app's pid doesn't scroll, even with the target window set on the event (tested on macOS 26).
    /// Marked continuous, like trackpad scrolling, so apps apply each small delta as is instead of
    /// animating it as a mouse-wheel notch.
    private func post(dx: Int32, dy: Int32, at point: CGPoint) {
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                                  wheel1: dy, wheel2: dx, wheel3: 0) else { return }
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.location = point
        event.post(tap: .cgSessionEventTap)
    }
}
