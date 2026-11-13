import Foundation

/// The distance a smooth scroll covers frame by frame, along one direction. Advanced by the scroller
/// at display rate; each call returns how far to move during that frame.
public struct ScrollMotion: Equatable {
    /// While a key is held: start at `startSpeed`, speed up by `acceleration` up to `maxSpeed`
    /// (points per second). On release, ease out over `settleTime`, covering at least
    /// `minimumDistance` in total so a quick tap still moves one step.
    public static let startSpeed: CGFloat = 900
    public static let maxSpeed: CGFloat = 2600
    public static let acceleration: CGFloat = 2200
    public static let settleTime: TimeInterval = 0.14
    public static let minimumDistance: CGFloat = ScrollCommand.step

    private enum Phase: Equatable {
        case held
        /// Ease-out of `distance` over `duration`; `elapsed` so far.
        case easing(distance: CGFloat, duration: TimeInterval, elapsed: TimeInterval)
        case finished
    }

    private var phase: Phase
    private var speed: CGFloat = ScrollMotion.startSpeed
    public private(set) var travelled: CGFloat = 0

    public var isFinished: Bool { phase == .finished }

    /// Follows a held key until it's released.
    public static func held() -> ScrollMotion { ScrollMotion(phase: .held) }

    /// A fixed distance with an ease-out, e.g. half a page.
    public static func eased(distance: CGFloat, duration: TimeInterval) -> ScrollMotion {
        ScrollMotion(phase: .easing(distance: distance, duration: duration, elapsed: 0))
    }

    private init(phase: Phase) {
        self.phase = phase
    }

    /// Distance to move during the next `dt` seconds. `held` is whether the key is still down.
    public mutating func advance(dt: TimeInterval, held: Bool) -> CGFloat {
        switch phase {
        case .finished:
            return 0
        case .held:
            guard held else {
                // Released: a short tap finishes exactly one step; a hold glides out.
                let distance = travelled < Self.minimumDistance
                    ? Self.minimumDistance - travelled
                    : speed * CGFloat(Self.settleTime) / 2
                phase = .easing(distance: distance, duration: Self.settleTime, elapsed: 0)
                return advance(dt: dt, held: false)
            }
            let step = speed * CGFloat(dt)
            speed = min(Self.maxSpeed, speed + Self.acceleration * CGFloat(dt))
            travelled += step
            return step
        case .easing(let distance, let duration, let elapsed):
            let now = min(duration, elapsed + dt)
            let step = distance * (Self.easeOut(now / duration) - Self.easeOut(elapsed / duration))
            travelled += step
            phase = now >= duration ? .finished : .easing(distance: distance, duration: duration, elapsed: now)
            return step
        }
    }

    /// Cubic ease-out: fast start, gentle stop.
    static func easeOut(_ t: TimeInterval) -> CGFloat {
        let u = 1 - min(max(t, 0), 1)
        return CGFloat(1 - u * u * u)
    }
}
