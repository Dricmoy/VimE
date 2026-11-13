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
    /// Apps where every key matters. Terminals are Off: ⌥F is "forward word" in shells and Emacs.
    public static let defaults: [String: AppRule] = [
        "com.apple.Terminal": .off,
        "com.googlecode.iterm2": .off,
        "com.mitchellh.ghostty": .off,
        "net.kovidgoyal.kitty": .off,
        "org.alacritty": .off,
        "dev.warp.Warp-Stable": .off,
        "org.vim.MacVim": .chordOnly,
        "com.qvacua.VimR": .chordOnly,
        // Games and the windows of other computers run inside these, and every key belongs to them.
        "com.codeweavers.CrossOver": .off,
        "com.isaacmarovitz.Whisky": .off,
        "com.nvidia.gfnpc.mall": .off,
        "com.parallels.desktop.console": .off,
        "com.vmware.fusion": .off,
        "com.utmapp.UTM": .off,
        "com.microsoft.rdc.macos": .off,
    ]

    /// What apps without a rule of their own get. Plain keys are opt-in: unlisted apps get ⌥F only,
    /// so games and editors keep their keys until you switch an app on.
    public static let standardFallback: AppRule = .chordOnly

    public private(set) var overrides: [String: AppRule]
    public var fallback: AppRule
    /// Apps recognised as games (see `Policy.isGame`). Off unless you've set them yourself.
    public var detectedGames: Set<String> = []

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
        Self.defaults[bundleID] ?? (detectedGames.contains(bundleID) ? .off : fallback)
    }

    /// Off because it was recognised as a game, not because you set it.
    public func isOffAsGame(_ bundleID: String) -> Bool {
        overrides[bundleID] == nil && Self.defaults[bundleID] == nil && detectedGames.contains(bundleID)
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
        let ids = Set(overrides.keys).union(Self.defaults.keys).union(detectedGames)
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
    /// Game launchers and stores: they may carry the games category, but they're ordinary windows.
    static let gameLaunchers: Set<String> = [
        "com.valvesoftware.steam", "com.epicgames.EpicGamesLauncher", "com.gog.galaxy",
        "com.blizzard.bnetlauncher", "com.apple.games",
    ]

    /// Whether an app looks like a game, from what its bundle says about itself. `frameworks` lists
    /// Contents/Frameworks; `path` is where the app lives.
    public static func isGame(bundleID: String?, category: String?, supportsGameMode: Bool, path: String,
                              frameworks: [String]) -> Bool {
        if let bundleID, gameLaunchers.contains(bundleID) { return false }
        if let category, category == "public.app-category.games" || category.hasSuffix("-games") { return true }
        if supportsGameMode { return true }
        if path.contains("/steamapps/common/") { return true }
        // Game engines: Unity, and the Mono runtime Unity and many indie engines embed.
        return frameworks.contains { $0 == "UnityPlayer.dylib" || $0.hasPrefix("libmonobdwgc") || $0 == "Mono.framework" }
    }

    public static func isChromiumBrowser(bundleID: String?, frameworks: [String]) -> Bool {
        if let bundleID, chromiumBrowserIDs.contains(bundleID) { return true }
        return frameworks.contains { $0.hasSuffix(" Framework.framework") && $0 != "Electron Framework.framework" }
    }
}
