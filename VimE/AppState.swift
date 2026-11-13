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
    @Published var appRules = AppRules(plist: UserDefaults.standard.dictionary(forKey: "appRules") as? [String: String] ?? [:],
                                       fallback: AppState.loadDefaultRule()) {
        didSet {
            UserDefaults.standard.set(appRules.plist, forKey: "appRules")
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

    private static func load(_ key: String, default value: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? value
    }

    private func save(_ key: String, _ value: Bool) {
        UserDefaults.standard.set(value, forKey: key)
        onChange()
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
