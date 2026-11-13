/// Per-app behaviour switches beyond the On / ⌥F only / Off rule. Each has a global default the
/// user can change, and any app can override it either way.
public enum AppOption: String, CaseIterable {
    /// In an app that's On, Esc in a text field moves focus out of it so plain keys work again.
    /// Web content only (browsers, Electron apps); native apps keep their own Esc.
    case escLeavesTextField

    public var builtInDefault: Bool {
        switch self {
        case .escLeavesTextField: return true
        }
    }
}

public struct AppOptions: Equatable {
    /// The user's global defaults; options missing here use `builtInDefault`.
    public var defaults: [AppOption: Bool]
    public private(set) var overrides: [String: [AppOption: Bool]]

    public init(defaults: [AppOption: Bool] = [:], overrides: [String: [AppOption: Bool]] = [:]) {
        self.defaults = defaults
        self.overrides = overrides
    }

    public func defaultValue(_ option: AppOption) -> Bool {
        defaults[option] ?? option.builtInDefault
    }

    public func value(_ option: AppOption, for bundleID: String?) -> Bool {
        bundleID.flatMap { overrides[$0]?[option] } ?? defaultValue(option)
    }

    /// The app's own setting, or nil when it follows the default.
    public func override(_ option: AppOption, for bundleID: String) -> Bool? {
        overrides[bundleID]?[option]
    }

    /// `nil` makes the app follow the default again.
    public mutating func set(_ option: AppOption, _ value: Bool?, for bundleID: String) {
        var forApp = overrides[bundleID] ?? [:]
        forApp[option] = value
        overrides[bundleID] = forApp.isEmpty ? nil : forApp
    }

    /// For UserDefaults: `["com.example.App": ["escLeavesTextField": false]]`.
    public var plist: [String: [String: Bool]] {
        overrides.mapValues { Dictionary(uniqueKeysWithValues: $0.map { ($0.key.rawValue, $0.value) }) }
    }

    public var defaultsPlist: [String: Bool] {
        Dictionary(uniqueKeysWithValues: defaults.map { ($0.key.rawValue, $0.value) })
    }

    public init(defaultsPlist: [String: Bool], plist: [String: [String: Bool]]) {
        func decode(_ d: [String: Bool]) -> [AppOption: Bool] {
            Dictionary(uniqueKeysWithValues: d.compactMap { k, v in AppOption(rawValue: k).map { ($0, v) } })
        }
        self.defaults = decode(defaultsPlist)
        self.overrides = plist.mapValues(decode).filter { !$0.value.isEmpty }
    }
}
