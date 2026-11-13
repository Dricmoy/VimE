import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VimECore

struct SettingsView: View {
    @ObservedObject var state: AppState
    var runSetup: () -> Void

    var body: some View {
        TabView {
            general.tabItem { Label("General", systemImage: "gearshape") }
            apps.tabItem { Label("Apps", systemImage: "square.grid.2x2") }
            AppearanceTab(state: state).tabItem { Label("Appearance", systemImage: "paintpalette") }
            keys.tabItem { Label("Keys", systemImage: "keyboard") }
        }
        .frame(width: 520, height: 600)
    }

    private var general: some View {
        Form {
            Section {
                Toggle("Enable VimE", isOn: $state.enabled).toggleStyle(.switch)
            }

            Section("General") {
                PreferenceToggles(state: state)
                Toggle(isOn: Binding(get: { state.appOptions.defaultValue(.escLeavesTextField) },
                                     set: { state.appOptions.defaults[.escLeavesTextField] = $0 })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Esc leaves text fields")
                        Text("In apps that are On: Esc in a text field on a web page or in an Electron app moves you out of it, so plain keys work again. Change it per app in Apps.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
            }

            Section {
                Toggle("Tell me when a new version is out", isOn: $state.checkForUpdates).toggleStyle(.switch)
                HStack {
                    Text("VimE \(UpdateChecker.currentVersion)")
                    if let status = state.updateStatus {
                        Text("· \(status)").foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let release = state.availableRelease {
                        Button("Release Notes…") { NSWorkspace.shared.open(release.page) }
                    }
                    Button("Check Now") { state.checkForUpdatesNow() }
                }
            } header: {
                Text("Updates")
            } footer: {
                Text("Checks GitHub once a day and only reads the latest version number. To update: brew upgrade --cask vime, or download it from the releases page.")
                    .foregroundStyle(.secondary)
            }

            Section("Permissions") {
                HStack {
                    Circle().fill(state.trusted ? Color.green : Color.orange).frame(width: 9, height: 9)
                    Text(state.trusted ? "Accessibility access granted" : "Accessibility access needed")
                    Spacer()
                    Button("Run Setup…", action: runSetup)
                }
            }

            Section {
                HStack {
                    Button("Export…", action: exportSettings)
                    Button("Import…", action: importSettings)
                }
            } header: {
                Text("Other Macs")
            } footer: {
                Text("Copies your preferences, app rules and appearance to a file you can import on another Mac.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var apps: some View {
        Form {
            Section {
                ForEach(listedApps, id: \.self) { id in
                    AppRuleRow(bundleID: id, state: state)
                }
                Button("Add App…", action: addApp)
            } header: {
                Text("Apps")
            } footer: {
                Text("⌥F only: plain keys go to the app, ⌥F still shows hints. Off: VimE ignores the app. "
                     + "Apps not listed follow \"Apps you haven't set\" in General. Games VimE recognises start Off. "
                     + "The menu bar icon or ⌃⌥⌘⇧V switches the app you're in.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var keys: some View {
        Form {
            Section("Shortcuts") {
                ShortcutRows(shortcuts: Shortcuts.anywhere(plainKeys: state.bareKeys))
            }

            Section("While hints are showing") {
                ShortcutRows(shortcuts: Shortcuts.inHints)
            }
        }
        .formStyle(.grouped)
    }

    /// Apps with a rule or an option of their own.
    private var listedApps: [String] {
        Set(state.appRules.listed).union(state.appOptions.overrides.keys).sorted()
            .filter { AppInfo.isInstalled($0) || state.appRules.overrides[$0] != nil
                || state.appOptions.overrides[$0] != nil }
    }

    private func exportSettings() {
        let panel = NSSavePanel()
        panel.title = "Export VimE Settings"
        panel.nameFieldStringValue = "VimE Settings.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try state.archive.encoded().write(to: url, options: .atomic)
        } catch {
            showError("Couldn't export settings", error.localizedDescription)
        }
    }

    private func importSettings() {
        let panel = NSOpenPanel()
        panel.title = "Import VimE Settings"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let archive: SettingsArchive
        do {
            archive = try SettingsArchive.decode(Data(contentsOf: url))
        } catch SettingsArchive.ReadError.newerVersion {
            return showError("Couldn't import settings", "They're from a newer version of VimE. Update VimE first.")
        } catch {
            return showError("Couldn't import settings", "That file isn't a VimE settings export.")
        }
        let confirm = NSAlert()
        confirm.messageText = "Replace your VimE settings?"
        confirm.informativeText = "Your preferences and app rules will be replaced with the ones in "
            + "\"\(url.lastPathComponent)\" (\(archive.appRules.count) app rules)."
        confirm.addButton(withTitle: "Replace")
        confirm.addButton(withTitle: "Cancel")
        guard confirm.runModal() == .alertFirstButtonReturn else { return }
        state.apply(archive)
    }

    private func showError(_ title: String, _ detail: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.runModal()
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.title = "Choose an App"
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let id = Bundle(url: url)?.bundleIdentifier else { continue }
            // Adding an app means "not like the rest": On when others are opt-in, else ⌥F only.
            guard state.appRules.overrides[id] == nil else { continue }
            state.appRules.set(state.defaultRule == .normal ? .chordOnly : .normal, for: id)
        }
    }
}

private struct AppearanceTab: View {
    @ObservedObject var state: AppState

    var body: some View {
        Form {
            Section("Hints") {
                Picker("Style", selection: $state.badgeStyle) {
                    ForEach(BadgeStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("Size", selection: $state.badgeSize) {
                    ForEach(BadgeSize.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                BadgePreview(style: state.badgeStyle, size: state.badgeSize)
            }

            Section {
                Picker("Position", selection: $state.indicatorPosition) {
                    ForEach(IndicatorPosition.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Toggle(isOn: $state.indicatorWhileTyping) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Also while typing")
                        Text("Show it whenever you're in a text field in an app that's On, so you know plain keys will type.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .disabled(state.indicatorPosition == .hidden)
            } header: {
                Text("Mode indicator")
            } footer: {
                Text("Shows -- INSERT -- after you press i, when every key goes to the app until Esc.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// Sample badges over a light and a dark window, drawn like the real ones.
struct BadgePreview: View {
    let style: BadgeStyle
    let size: BadgeSize

    var body: some View {
        HStack(spacing: 10) {
            sample(background: .white, text: .black)
            sample(background: Color(white: 0.13), text: .white)
        }
        .padding(.vertical, 4)
    }

    private func sample(background: Color, text: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(["Inbox", "Compose", "Settings"].enumerated()), id: \.offset) { i, word in
                ZStack(alignment: .topLeading) {
                    Text(word).font(.system(size: 13)).foregroundStyle(text).padding(.leading, 14).padding(.top, 6)
                    HintBadge(text: ["A", "SD", "F"][i], style: style, size: size, typed: i == 1 ? "S" : "")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))
    }
}

extension BadgeStyle {
    var title: String {
        switch self {
        case .auto: return "Auto (opposite of Light/Dark mode)"
        case .dark: return "Dark"
        case .light: return "Light"
        case .classic: return "Classic yellow"
        }
    }
}

extension BadgeSize {
    var title: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }
}

extension IndicatorPosition {
    var title: String {
        switch self {
        case .hidden: return "Hidden"
        case .topLeft: return "Top left"
        case .topRight: return "Top right"
        case .bottomLeft: return "Bottom left"
        case .bottomRight: return "Bottom right"
        }
    }
}

private struct AppRuleRow: View {
    let bundleID: String
    @ObservedObject var state: AppState

    var body: some View {
        HStack {
            Image(nsImage: AppInfo.icon(bundleID)).resizable().frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(AppInfo.name(bundleID))
                if state.appRules.isOffAsGame(bundleID) {
                    Text("Looks like a game").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Picker("", selection: Binding(get: { state.appRules.rule(for: bundleID) },
                                          set: { state.appRules.set($0, for: bundleID) })) {
                ForEach(AppRule.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
            Menu {
                Picker("Esc leaves text fields", selection: Binding(
                    get: { state.appOptions.override(.escLeavesTextField, for: bundleID) },
                    set: { state.appOptions.set(.escLeavesTextField, $0, for: bundleID) })) {
                    Text("Default (\(state.appOptions.defaultValue(.escLeavesTextField) ? "On" : "Off"))").tag(Bool?.none)
                    Text("On").tag(Bool?.some(true))
                    Text("Off").tag(Bool?.some(false))
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("More options for \(AppInfo.name(bundleID))")
            if state.appRules.overrides[bundleID] != nil || state.appOptions.overrides[bundleID] != nil,
               AppRules.defaults[bundleID] == nil {
                Button {
                    state.appRules.reset(bundleID)
                    for option in AppOption.allCases { state.appOptions.set(option, nil, for: bundleID) }
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .help("Remove")
            }
        }
    }
}

extension AppRule {
    var title: String {
        switch self {
        case .normal: return "On"
        case .chordOnly: return "⌥F only"
        case .off: return "Off"
        }
    }

    var detail: String {
        switch self {
        case .normal: return "Plain keys outside text fields, and ⌥F"
        case .chordOnly: return "Plain keys go to the app; ⌥F still shows hints"
        case .off: return "VimE ignores this app"
        }
    }
}

enum AppInfo {
    static func isInstalled(_ bundleID: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    static func name(_ bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    static func icon(_ bundleID: String) -> NSImage {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return NSWorkspace.shared.icon(for: .application)
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

final class SettingsWindow {
    private var window: NSWindow?

    func show(state: AppState, runSetup: @escaping () -> Void) {
        state.trusted = Permissions.isTrusted(prompt: false)
        state.launchAtLogin = LoginItem.isEnabled
        if window == nil {
            let host = NSHostingController(rootView: SettingsView(state: state, runSetup: runSetup))
            let window = NSWindow(contentViewController: host)
            window.title = "VimE Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            self.window = window
        }
        Windows.present(window!)
    }

    func close() {
        window?.close()
    }
}
