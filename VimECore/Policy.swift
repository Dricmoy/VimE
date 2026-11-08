/// What VimE does in one app.
public enum AppRule: String, CaseIterable {
    /// Plain keys outside text fields, plus ⌥F.
    case normal
    /// Only ⌥F; every plain key goes to the app.
    case chordOnly
    /// VimE ignores the app entirely.
    case off
}

/// Per-app rules: the user's overrides, then built-in defaults, then `fallback` for every other app.
public struct AppRules: Equatable {
    /// Apps where every key matters.
    public static let defaults: [String: AppRule] = [
        "com.apple.Terminal": .chordOnly,
        "com.googlecode.iterm2": .chordOnly,
        "com.mitchellh.ghostty": .chordOnly,
        "net.kovidgoyal.kitty": .chordOnly,
        "org.alacritty": .chordOnly,
        "dev.warp.Warp-Stable": .chordOnly,
        "org.vim.MacVim": .chordOnly,
        "com.qvacua.VimR": .chordOnly,
    ]

    /// What apps without a rule of their own get. Plain keys are opt-in: unlisted apps get ⌥F only,
    /// so games and editors keep their keys until you switch an app on.
    public static let standardFallback: AppRule = .chordOnly

    public private(set) var overrides: [String: AppRule]
    public var fallback: AppRule

    public init(overrides: [String: AppRule] = [:], fallback: AppRule = Self.standardFallback) {
        self.overrides = overrides
        self.fallback = fallback
    }

    public func rule(for bundleID: String?) -> AppRule {
        guard let bundleID else { return fallback }
        return overrides[bundleID] ?? builtIn(bundleID)
    }

    /// The rule an app has without an override.
    public func builtIn(_ bundleID: String) -> AppRule {
        Self.defaults[bundleID] ?? fallback
    }

    /// The next rule in On → ⌥F only → Off → On, for the cycle shortcut.
    public mutating func cycle(_ bundleID: String) -> AppRule {
        let next: AppRule
        switch rule(for: bundleID) {
        case .normal: next = .chordOnly
        case .chordOnly: next = .off
        case .off: next = .normal
        }
        set(next, for: bundleID)
        return next
    }

    /// Stores only what differs from the default, so changed defaults reach users who never touched them.
    public mutating func set(_ rule: AppRule, for bundleID: String) {
        if rule == builtIn(bundleID) {
            overrides[bundleID] = nil
        } else {
            overrides[bundleID] = rule
        }
    }

    /// Back to the built-in rule.
    public mutating func reset(_ bundleID: String) {
        overrides[bundleID] = nil
    }

    /// Apps with a rule other than normal, or with any override; what Settings lists.
    public var listed: [String] {
        let ids = Set(overrides.keys).union(Self.defaults.keys)
        return ids.sorted()
    }

    /// For UserDefaults.
    public var plist: [String: String] {
        overrides.mapValues(\.rawValue)
    }

    public init(plist: [String: String], fallback: AppRule = Self.standardFallback) {
        self.overrides = plist.compactMapValues(AppRule.init(rawValue:))
        self.fallback = fallback
    }
}

public enum Policy {
    /// Chromium browsers whose bundles don't follow the framework naming below.
    static let chromiumBrowserIDs: Set<String> = ["company.thebrowser.Browser", "company.thebrowser.dia"]

    /// Chromium browsers (Chrome, Brave, Edge, Vivaldi…) ship a "<Name> Framework.framework"; Electron apps
    /// ship "Electron Framework.framework" and answer the lighter AXManualAccessibility switch instead.
    public static func isChromiumBrowser(bundleID: String?, frameworks: [String]) -> Bool {
        if let bundleID, chromiumBrowserIDs.contains(bundleID) { return true }
        return frameworks.contains { $0.hasSuffix(" Framework.framework") && $0 != "Electron Framework.framework" }
    }
}
