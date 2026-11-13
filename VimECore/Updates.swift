import Foundation

/// A release number like `1.2.3`. A leading `v` is allowed, and a pre-release or build suffix
/// (`-beta.1`, `+5`) is ignored. Missing trailing parts count as zero, so `1.2` equals `1.2.0`.
public struct ReleaseVersion: Comparable, CustomStringConvertible {
    public let parts: [Int]

    public init?(_ string: String) {
        var text = Substring(string.trimmingCharacters(in: .whitespaces))
        if text.first == "v" || text.first == "V" { text = text.dropFirst() }
        let core = text.prefix { $0 != "-" && $0 != "+" }
        let numbers = core.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard (1...4).contains(numbers.count) else { return nil }
        var parts: [Int] = []
        for number in numbers {
            guard let number, number >= 0 else { return nil }
            parts.append(number)
        }
        while parts.count > 1, parts.last == 0 { parts.removeLast() }
        self.parts = parts
    }

    public static func < (a: ReleaseVersion, b: ReleaseVersion) -> Bool {
        for i in 0..<max(a.parts.count, b.parts.count) {
            let x = i < a.parts.count ? a.parts[i] : 0
            let y = i < b.parts.count ? b.parts[i] : 0
            if x != y { return x < y }
        }
        return false
    }

    public var description: String {
        (parts + Array(repeating: 0, count: max(0, 3 - parts.count))).map(String.init).joined(separator: ".")
    }
}

/// When to ask GitHub for the latest release, and whether it's newer than this copy of VimE.
public enum UpdateCheck {
    public static let interval: TimeInterval = 24 * 60 * 60

    public static func isDue(lastCheck: Date?, now: Date) -> Bool {
        guard let lastCheck else { return true }
        // A clock set backwards counts as due, so a bad timestamp can't stop checks for good.
        return now.timeIntervalSince(lastCheck) >= interval || now < lastCheck
    }

    /// The latest release's version, when it's newer than `current`. Unreadable versions never count.
    public static func newer(latestTag: String, current: String) -> ReleaseVersion? {
        guard let latest = ReleaseVersion(latestTag), let current = ReleaseVersion(current),
              current < latest else { return nil }
        return latest
    }
}
