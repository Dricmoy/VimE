import CoreGraphics

/// How hint badges look. The colours themselves live in the app; this is the stored choice.
public enum BadgeStyle: String, CaseIterable {
    /// Dark badges while macOS is in Light mode, light badges in Dark mode, so they stand out from
    /// the windows they sit on, which mostly follow the system appearance.
    case auto
    case dark
    case light
    /// The original yellow, like Vimium.
    case classic
}

public enum BadgeSize: String, CaseIterable {
    case small
    case medium
    case large

    public var fontSize: CGFloat {
        switch self {
        case .small: return 11
        case .medium: return 12.5
        case .large: return 14
        }
    }
}

/// Where badges go, in top-left-origin coordinates (y grows downwards).
public enum BadgeLayout {
    /// How far a badge sits up and left of its element's corner, so it covers less of the element's text.
    public static let nudge: CGFloat = 3

    /// The badge for an element: its top-left corner nudged out a little.
    public static func anchor(element: CGRect, size: CGSize) -> CGRect {
        CGRect(x: element.minX - nudge, y: element.minY - nudge, width: size.width, height: size.height)
    }

    /// Moves badges apart so none covers another, keeping each near its element. Badges are placed in
    /// reading order; one that lands on an earlier badge moves right past it, or below it when there's no
    /// room to the right. All stay inside `bounds`. Returns the badges in the order given.
    public static func place(_ badges: [CGRect], in bounds: CGRect, gap: CGFloat = 1) -> [CGRect] {
        let order = badges.indices.sorted {
            let a = badges[$0], b = badges[$1]
            return a.minY != b.minY ? a.minY < b.minY : a.minX < b.minX
        }
        var placed: [CGRect] = []
        var result = badges
        for i in order {
            var badge = clamp(badges[i], to: bounds)
            // A handful of moves is enough in practice; past that, an overlap beats a missing badge.
            for _ in 0..<12 {
                guard let other = placed.first(where: { $0.insetBy(dx: -gap / 2, dy: -gap / 2).intersects(badge) })
                else { break }
                if other.maxX + gap + badge.width <= bounds.maxX {
                    badge.origin.x = other.maxX + gap
                } else {
                    badge.origin = CGPoint(x: badges[i].minX, y: other.maxY + gap)
                    badge = clamp(badge, to: bounds)
                }
            }
            placed.append(badge)
            result[i] = badge
        }
        return result
    }

    static func clamp(_ r: CGRect, to bounds: CGRect) -> CGRect {
        var r = r
        r.origin.x = min(max(r.minX, bounds.minX), bounds.maxX - r.width)
        r.origin.y = min(max(r.minY, bounds.minY), bounds.maxY - r.height)
        return r
    }
}

/// Where the mode indicator sits on the screen you're working on.
public enum IndicatorPosition: String, CaseIterable {
    case hidden
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
}
