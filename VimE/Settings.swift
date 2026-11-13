import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VimECore

struct SettingsView: View {
    @ObservedObject var state: AppState
    var runSetup: () -> Void

    var body: some View {
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
                        Text("In apps that are On: Esc in a text field on a web page or in an Electron app moves you out of it, so plain keys work again. Change it per app below.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
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
                ForEach(listedApps, id: \.self) { id in
                    AppRuleRow(bundleID: id, state: state)
                }
                Button("Add App…", action: addApp)
            } header: {
                Text("Apps")
            } footer: {
                Text("⌥F only: plain keys go to the app, ⌥F still shows hints. Off: VimE ignores the app. "
                     + "Apps not listed follow \"Apps you haven't set\" above. "
                     + "The menu bar icon or ⌃⌥⌘⇧V switches the app you're in.")
                    .foregroundStyle(.secondary)
            }

            Section("Shortcuts") {
                ShortcutRows(shortcuts: Shortcuts.anywhere(plainKeys: state.bareKeys))
            }

            Section("While hints are showing") {
                ShortcutRows(shortcuts: Shortcuts.inHints)
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 720)
    }

    /// Apps with a rule or an option of their own.
    private var listedApps: [String] {
        Set(state.appRules.listed).union(state.appOptions.overrides.keys).sorted()
            .filter { AppInfo.isInstalled($0) || state.appRules.overrides[$0] != nil
                || state.appOptions.overrides[$0] != nil }
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

private struct AppRuleRow: View {
    let bundleID: String
    @ObservedObject var state: AppState

    var body: some View {
        HStack {
            Image(nsImage: AppInfo.icon(bundleID)).resizable().frame(width: 20, height: 20)
            Text(AppInfo.name(bundleID))
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
