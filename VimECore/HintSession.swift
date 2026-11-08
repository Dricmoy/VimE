/// Tracks what the user has typed while hint labels are on screen.
public struct HintSession {
    public enum Outcome: Equatable {
        case narrowed
        case matched(Int)
        case noMatch
    }

    public let labels: [String]
    public private(set) var typed = ""

    public init(labels: [String]) {
        self.labels = labels
    }

    /// Adds a character. A character that matches nothing is ignored, so a typo doesn't lose progress.
    public mutating func type(_ c: Character) -> Outcome {
        let next = typed + c.lowercased()
        let matches = labels.indices.filter { labels[$0].hasPrefix(next) }
        guard !matches.isEmpty else { return .noMatch }
        typed = next
        if let exact = matches.first(where: { labels[$0] == next }) { return .matched(exact) }
        return .narrowed
    }

    public mutating func backspace() {
        if !typed.isEmpty { typed.removeLast() }
    }

    public func isVisible(_ index: Int) -> Bool {
        labels[index].hasPrefix(typed)
    }
}
