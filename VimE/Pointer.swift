import AppKit

/// The mouse pointer, for events that only reach a window through the pointer's position.
/// Everything here uses accessibility space (top-left origin of the primary display).
enum Pointer {
    static var location: CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    /// Whether a scroll or click at `point` reaches `pid`. Asks Accessibility which app is under the
    /// point: unlike the window list, it skips click-through overlays such as Notification Center's
    /// full-screen window. Falls back to the window list when Accessibility doesn't answer.
    static func isOverApp(_ pid: pid_t, at point: CGPoint) -> Bool {
        // No timeout here: one set on the system-wide element becomes every element's default.
        let system = AXUIElementCreateSystemWide()
        var hit: AXUIElement?
        var owner: pid_t = 0
        if AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success, let hit,
           AXUIElementGetPid(hit, &owner) == .success {
            return owner == pid
        }
        return topWindowOwner(at: point) == pid
    }

    /// Owner of the frontmost normal or floating window under the point. Higher layers (Dock, menu bar,
    /// Notification Center) are skipped: several of them are invisible and let events through.
    private static func topWindowOwner(at point: CGPoint) -> pid_t? {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                       kCGNullWindowID) as? [[String: Any]] else { return nil }
        let maxLayer = Int(CGWindowLevelForKey(.floatingWindow))
        let mine = getpid()
        for w in windows {
            guard let owner = w[kCGWindowOwnerPID as String] as? pid_t, owner != mine,
                  let layer = w[kCGWindowLayer as String] as? Int, layer >= 0, layer <= maxLayer,
                  (w[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let bounds = w[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds), rect.contains(point) else { continue }
            return owner
        }
        return nil
    }

    /// Puts the pointer back where it was, after events that moved it. A synthetic move rather than
    /// CGWarpMouseCursorPosition, which would ignore the real mouse for a quarter second afterwards.
    /// `tap` should match the one the earlier events went to, so this one is delivered after them.
    static func restore(to point: CGPoint, tap: CGEventTapLocation) {
        guard let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point,
                                 mouseButton: .left) else { return }
        move.post(tap: tap)
    }
}
