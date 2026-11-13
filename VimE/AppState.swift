import AppKit
import ServiceManagement
import VimECore

/// Shared state for the menu, Settings and setup.
final class AppState: ObservableObject {
    @Published var enabled = AppState.load("enabled", default: true) {
        didSet { save("enabled", enabled) }
    }
    @Published var showMenuBarIcon = AppState.load("showMenuBarIcon", default: true) {
        didSet { save("showMenuBarIcon", showMenuBarIcon) }
    }
    @Published var showInDock = AppState.load("showInDock", default: false) {
        didSet { save("showInDock", showInDock) }
    }
    /// Plain keys (f, hjkl…) act outside text fields; ⌥F always works.
    @Published var bareKeys = AppState.load("bareKeys", default: true) {
        didSet { save("bareKeys", bareKeys) }
    }
    /// What apps without their own rule get. ⌥F only by default, so plain keys are opt-in per app.
    @Published var defaultRule = AppState.loadDefaultRule() {
        didSet {
            UserDefaults.standard.set(defaultRule.rawValue, forKey: "defaultAppRule")
            appRules.fallback = defaultRule
        }
    }
    /// Per-app overrides (on, ⌥F only, off).
    @Published var appRules = AppState.loadRules() {
        didSet {
            UserDefaults.standard.set(appRules.plist, forKey: "appRules")
            UserDefaults.standard.set(appRules.detectedGames.sorted(), forKey: "detectedGames")
            onChange()
        }
    }
    /// Per-app behaviour switches and their global defaults.
    @Published var appOptions = AppOptions(
        defaultsPlist: UserDefaults.standard.dictionary(forKey: "appOptionDefaults") as? [String: Bool] ?? [:],
        plist: UserDefaults.standard.dictionary(forKey: "appOptions") as? [String: [String: Bool]] ?? [:]) {
        didSet {
            UserDefaults.standard.set(appOptions.defaultsPlist, forKey: "appOptionDefaults")
            UserDefaults.standard.set(appOptions.plist, forKey: "appOptions")
            onChange()
        }
    }
    @Published var badgeStyle = AppState.loadEnum("badgeStyle", default: BadgeStyle.auto) {
        didSet { saveEnum("badgeStyle", badgeStyle) }
    }
    @Published var badgeSize = AppState.loadEnum("badgeSize", default: BadgeSize.medium) {
        didSet { saveEnum("badgeSize", badgeSize) }
    }
    @Published var indicatorPosition = AppState.loadEnum("indicatorPosition", default: IndicatorPosition.bottomRight) {
        didSet { saveEnum("indicatorPosition", indicatorPosition) }
    }
    /// Also show the indicator while you type in a text field, not just in the `i` Insert mode.
    @Published var indicatorWhileTyping = AppState.load("indicatorWhileTyping", default: false) {
        didSet { save("indicatorWhileTyping", indicatorWhileTyping) }
    }
    /// Ask GitHub once a day whether a newer release is out. Never downloads anything.
    @Published var checkForUpdates = AppState.load("checkForUpdates", default: true) {
        didSet { save("checkForUpdates", checkForUpdates) }
    }
    /// What the last update check found, for the menu and Settings.
    @Published var availableRelease: UpdateChecker.Release?
    @Published var updateStatus: String?
    var checkForUpdatesNow: () -> Void = {}
    @Published var tapRunning = false {
        didSet { onChange() }
    }
    @Published var trusted = Permissions.isTrusted(prompt: false)
    @Published var launchAtLogin = LoginItem.isEnabled
    @Published var loginError: String?

    var onChange: () -> Void = {}

    private static func loadDefaultRule() -> AppRule {
        UserDefaults.standard.string(forKey: "defaultAppRule").flatMap(AppRule.init(rawValue:)) ?? AppRules.standardFallback
    }

    private static func loadRules() -> AppRules {
        var rules = AppRules(plist: UserDefaults.standard.dictionary(forKey: "appRules") as? [String: String] ?? [:],
                             fallback: loadDefaultRule())
        rules.detectedGames = Set(UserDefaults.standard.stringArray(forKey: "detectedGames") ?? [])
        return rules
    }

    private static func loadEnum<E: RawRepresentable>(_ key: String, default value: E) -> E where E.RawValue == String {
        UserDefaults.standard.string(forKey: key).flatMap(E.init(rawValue:)) ?? value
    }

    private func saveEnum<E: RawRepresentable>(_ key: String, _ value: E) where E.RawValue == String {
        UserDefaults.standard.set(value.rawValue, forKey: key)
        onChange()
    }

    private static func load(_ key: String, default value: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? value
    }

    private func save(_ key: String, _ value: Bool) {
        UserDefaults.standard.set(value, forKey: key)
        onChange()
    }

    /// Preferences and per-app rules, for another Mac.
    var archive: SettingsArchive {
        SettingsArchive(plainKeys: bareKeys, showMenuBarIcon: showMenuBarIcon, showInDock: showInDock,
                        defaultRule: defaultRule, rules: appRules, options: appOptions, badgeStyle: badgeStyle,
                        badgeSize: badgeSize, indicatorPosition: indicatorPosition,
                        indicatorWhileTyping: indicatorWhileTyping)
    }

    /// Replaces preferences and per-app rules. Leaves enabled or paused and launch at login alone.
    func apply(_ archive: SettingsArchive) {
        bareKeys = archive.plainKeys
        showMenuBarIcon = archive.showMenuBarIcon
        showInDock = archive.showInDock
        defaultRule = archive.rule
        var rules = archive.rules
        rules.detectedGames = appRules.detectedGames  // Detected on this Mac, not part of the export.
        appRules = rules
        appOptions = archive.options
        if let style = archive.style { badgeStyle = style }
        if let size = archive.size { badgeSize = size }
        if let indicator = archive.indicator { indicatorPosition = indicator }
        if let typing = archive.indicatorWhileTyping { indicatorWhileTyping = typing }
    }

    func setLaunchAtLogin(_ on: Bool) {
        loginError = LoginItem.set(on)
        launchAtLogin = LoginItem.isEnabled
    }
}

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Returns an error message, or nil on success.
    static func set(_ on: Bool) -> String? {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}

enum Windows {
    /// Activation is cooperative on macOS 14+, so a background app also orders its window front explicitly.
    static func present(_ window: NSWindow) {
        if let screen = NSScreen.main?.visibleFrame, !window.isVisible {
            let size = window.frame.size
            window.setFrameOrigin(NSPoint(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2))
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}
