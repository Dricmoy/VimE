import CoreGraphics

/// Checks for things the Accessibility tree still reports after they've left the screen.
public enum Visibility {
    /// Whether a menu bar item is on screen. An auto-hidden menu bar keeps reporting its items at the
    /// top of the screen while the window server has slid the bar itself away.
    ///
    /// - shownBars: the window server's menu bar windows (one per display), accessibility space.
    ///   Empty means they couldn't be read, so the item is kept.
    public static func isMenuBarItemShown(_ item: CGRect, shownBars: [CGRect]) -> Bool {
        guard !shownBars.isEmpty else { return true }
        let center = CGPoint(x: item.midX, y: item.midY)
        return shownBars.contains { $0.contains(center) }
    }
}
