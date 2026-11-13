import CoreGraphics

public enum ScrollCommand: Equatable {
    case down, up, left, right
    case halfPageDown, halfPageUp
    case top, bottom

    /// Vimium's default step for j/k/h/l.
    public static let step: CGFloat = 60
    /// Far enough to reach either end of any document; apps clamp it. Sent as several events
    /// of at most `maxEventDelta`, because one huge delta overflows and can flip direction.
    public static let toEnd: CGFloat = 200_000
    public static let maxEventDelta: CGFloat = 20_000

    /// Pixel deltas for a scroll-wheel event. Quartz convention: positive `dy` scrolls up
    /// (toward the top), positive `dx` scrolls left.
    public func delta(viewport: CGSize) -> (dx: CGFloat, dy: CGFloat) {
        switch self {
        case .down: return (0, -Self.step)
        case .up: return (0, Self.step)
        case .left: return (Self.step, 0)
        case .right: return (-Self.step, 0)
        case .halfPageDown: return (0, -(viewport.height / 2).rounded())
        case .halfPageUp: return (0, (viewport.height / 2).rounded())
        case .top: return (0, Self.toEnd)
        case .bottom: return (0, -Self.toEnd)
        }
    }

    /// Number of events needed so none exceeds `maxEventDelta`.
    public static func minimumSteps(dx: CGFloat, dy: CGFloat) -> Int {
        Int((max(abs(dx), abs(dy)) / maxEventDelta).rounded(.up))
    }

    /// Splits a scroll into smaller events so it animates like a trackpad. Sums to the original.
    public static func steps(dx: CGFloat, dy: CGFloat, count: Int) -> [(dx: Int32, dy: Int32)] {
        guard count > 1 else { return [(Int32(dx), Int32(dy))] }
        var out: [(dx: Int32, dy: Int32)] = []
        var sentX: Int32 = 0, sentY: Int32 = 0
        for i in 1...count {
            let x = Int32((dx * CGFloat(i) / CGFloat(count)).rounded()) - sentX
            let y = Int32((dy * CGFloat(i) / CGFloat(count)).rounded()) - sentY
            sentX += x
            sentY += y
            out.append((x, y))
        }
        return out
    }

    /// Where to send scroll events. Scroll events land on whatever is under their location, and
    /// posting them moves the pointer there. So when the pointer is already over the area (and over
    /// the app, not a window on top of it), scroll right under it and leave it alone; otherwise aim at
    /// the area's center and put the pointer back afterwards.
    public static func aim(area: CGRect, pointer: CGPoint, pointerOverApp: Bool) -> (at: CGPoint, restorePointer: Bool) {
        if pointerOverApp, area.contains(pointer) { return (pointer, false) }
        return (CGPoint(x: area.midX, y: area.midY), true)
    }
}
