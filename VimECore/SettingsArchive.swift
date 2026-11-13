import Foundation

/// VimE's settings as a file, for copying them to another Mac. Holds the preferences and per-app rules,
/// not machine-specific state (enabled or paused, launch at login, the Accessibility grant).
public struct SettingsArchive: Codable, Equatable {
    public static let currentVersion = 1
    static let formatName = "VimE settings"

    public enum ReadError: Error, Equatable {
        case notVimESettings
        /// Written by a newer VimE that this one may misread.
        case newerVersion(Int)
    }

    public var format = SettingsArchive.formatName
    public var version = SettingsArchive.currentVersion
    public var plainKeys: Bool
    public var showMenuBarIcon: Bool
    public var showInDock: Bool
    /// `AppRule` raw value for apps without their own rule.
    public var defaultRule: String
    public var appRules: [String: String]
    public var appOptionDefaults: [String: Bool]
    public var appOptions: [String: [String: Bool]]

    public init(plainKeys: Bool, showMenuBarIcon: Bool, showInDock: Bool, defaultRule: AppRule,
                rules: AppRules, options: AppOptions) {
        self.plainKeys = plainKeys
        self.showMenuBarIcon = showMenuBarIcon
        self.showInDock = showInDock
        self.defaultRule = defaultRule.rawValue
        self.appRules = rules.plist
        self.appOptionDefaults = options.defaultsPlist
        self.appOptions = options.plist
    }

    /// Unknown rule or option names (from a newer version) are dropped rather than failing the import.
    public var rule: AppRule { AppRule(rawValue: defaultRule) ?? AppRules.standardFallback }
    public var rules: AppRules { AppRules(plist: appRules, fallback: rule) }
    public var options: AppOptions { AppOptions(defaultsPlist: appOptionDefaults, plist: appOptions) }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> SettingsArchive {
        struct Header: Decodable { var format: String?; var version: Int? }
        guard let header = try? JSONDecoder().decode(Header.self, from: data),
              header.format == formatName, let version = header.version else { throw ReadError.notVimESettings }
        guard version <= currentVersion else { throw ReadError.newerVersion(version) }
        do {
            return try JSONDecoder().decode(SettingsArchive.self, from: data)
        } catch {
            throw ReadError.notVimESettings
        }
    }
}
