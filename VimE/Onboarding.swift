import AppKit
import SwiftUI
import VimECore

final class OnboardingModel: ObservableObject {
    enum Step: Int, CaseIterable {
        case welcome, permission, preferences, tryIt, done
    }

    @Published var step: Step = .welcome
    @Published var trusted = Permissions.isTrusted(prompt: false)
    @Published var triedHint = false

    var onFinish: () -> Void = {}
    private var timer: Timer?
    private var prompted = false

    func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            let now = Permissions.isTrusted(prompt: false)
            guard now != self.trusted else { return }
            self.trusted = now
            if now && self.step == .permission { self.step = .preferences }
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    /// First click adds VimE to the Accessibility list via the system prompt; later clicks open the pane.
    func requestPermission() {
        if prompted {
            Permissions.openAccessibilitySettings()
        } else {
            prompted = true
            _ = Permissions.isTrusted(prompt: true)
        }
    }

    /// Removes a stale entry (VimE shows as on but isn't trusted), then asks again.
    func resetPermission() {
        Permissions.resetAccessibility()
        prompted = true
        _ = Permissions.isTrusted(prompt: true)
    }

    func next() {
        if let next = Step(rawValue: step.rawValue + 1) { step = next } else { onFinish() }
    }
}

struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("VimE").font(.largeTitle.bold())
                Text("vim everywhere").foregroundStyle(.secondary)
                Spacer()
                StepDots(current: model.step)
            }
            Group {
                switch model.step {
                case .welcome: welcome
                case .permission: permission
                case .preferences: preferences
                case .tryIt: tryIt
                case .done: done
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            HStack {
                if model.step != .welcome {
                    Button("Back") { model.step = OnboardingModel.Step(rawValue: model.step.rawValue - 1)! }
                }
                Spacer()
                Button(primaryTitle) { model.next() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.step == .permission && !model.trusted)
            }
        }
        .padding(28)
        .frame(width: 540, height: 460)
    }

    private var primaryTitle: String {
        switch model.step {
        case .welcome: return "Get Started"
        case .permission, .preferences: return "Continue"
        case .tryIt: return model.triedHint ? "Continue" : "Skip"
        case .done: return "Finish"
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Click anything without the mouse.").font(.title2.weight(.semibold))
            Text("Press **⌥F** in any app and every button, link and tab gets a short label. Type the label to click it. In apps you turn on, plain **f** does the same and **j** and **k** scroll, like Vim.")
            HStack(spacing: 8) {
                ForEach(["S", "A", "DF", "J"], id: \.self) { HintBadge(text: $0) }
            }
            .padding(.top, 4)
            Text("Setup takes about a minute.").foregroundStyle(.secondary)
        }
    }

    private var permission: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Allow Accessibility access").font(.title2.weight(.semibold))
            Text("VimE uses it to find the buttons in other apps and to notice when you press **f**. Nothing leaves your Mac.")
            HStack(spacing: 10) {
                Circle().fill(model.trusted ? Color.green : Color.orange).frame(width: 10, height: 10)
                Text(model.trusted ? "Access granted" : "Not granted yet")
                    .fontWeight(.medium)
                Spacer()
                if !model.trusted {
                    Button("Open System Settings") { model.requestPermission() }
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.1)))
            if !model.trusted {
                HStack(alignment: .firstTextBaseline) {
                    Text("Turn on **VimE** in the list. Already on but still not granted? That's a stale entry from an older build.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset Permission") { model.resetPermission() }
                }
            }
        }
    }

    private var preferences: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Make it yours").font(.title2.weight(.semibold))
            PreferenceToggles(state: state)
            Text("You can change all of this later in Settings.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var tryIt: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Try it").font(.title2.weight(.semibold))
            VStack(alignment: .leading, spacing: 8) {
                Label("Click on another app — Finder works.", systemImage: "1.circle")
                Label(plainKeysByDefault ? "Press **f**. In a text field, use **⌥F**." : "Press **⌥F**.",
                      systemImage: "2.circle")
                Label("Type a yellow label to click it. **Esc** cancels.", systemImage: "3.circle")
            }
            HStack(spacing: 10) {
                Image(systemName: model.triedHint ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundStyle(model.triedHint ? .green : .secondary)
                Text(model.triedHint ? "Nice — hints are working."
                                     : "Waiting for you to press \(plainKeysByDefault ? "f" : "⌥F")…")
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.1)))
        }
    }

    private var done: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("You're set").font(.title2.weight(.semibold))
            ShortcutRows(shortcuts: Shortcuts.anywhere(plainKeys: state.bareKeys))
            Text(state.bareKeys ? "Press **?** in any app to see every key, including right-click."
                                : "Every key, including right-click, is listed in Settings.")
                .font(.callout)
            Text(whereToFind)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

extension OnboardingView {
    /// Whether plain f works in an app you haven't set up, like Finder during setup.
    private var plainKeysByDefault: Bool { state.bareKeys && state.defaultRule == .normal }

    private var whereToFind: String {
        switch (state.showMenuBarIcon, state.showInDock) {
        case (true, true): return "VimE is in your menu bar and Dock. Open either for Settings."
        case (true, false): return "VimE lives in your menu bar. Click it for Settings or to pause."
        case (false, true): return "VimE is in your Dock. Click it for Settings."
        case (false, false): return "VimE runs out of sight. Open it from Spotlight or Raycast to get back to Settings."
        }
    }
}

/// The choices shared by setup and Settings.
struct PreferenceToggles: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: Binding(get: { state.launchAtLogin }, set: { state.setLaunchAtLogin($0) })) {
                labeled("Open at login", "Start VimE quietly when you log in.")
            }
            if let error = state.loginError {
                Text(error).font(.callout).foregroundStyle(.red)
            }
            Toggle(isOn: $state.showMenuBarIcon) {
                labeled("Show in menu bar", "A quick on/off switch at the top of the screen.")
            }
            Toggle(isOn: $state.showInDock) {
                labeled("Show in Dock", "Also shows VimE in ⌘-Tab.")
            }
            if !state.showMenuBarIcon && !state.showInDock {
                Text("VimE will run out of sight. Open it from Spotlight or Raycast to change settings.")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
            Toggle(isOn: $state.bareKeys) {
                labeled("Plain keys", "f for hints, hjkl to scroll. Never fire while you type in a text field. ⌥F always works.")
            }
            Picker(selection: $state.defaultRule) {
                ForEach(AppRule.allCases, id: \.self) { Text($0.title).tag($0) }
            } label: {
                labeled("Apps you haven't set", "⌥F only keeps their keys safe. Turn an app On from the menu bar or with ⌃⌥⌘⇧V.")
            }
        }
        .toggleStyle(.switch)
    }

    private func labeled(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct StepDots: View {
    let current: OnboardingModel.Step

    var body: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingModel.Step.allCases, id: \.self) { step in
                Circle()
                    .fill(step.rawValue <= current.rawValue ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 7, height: 7)
            }
        }
    }
}

/// A badge drawn with the same colours as the real hints.
struct HintBadge: View {
    let text: String
    var style: BadgeStyle = .auto
    var size: BadgeSize = .large
    var typed = ""
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = BadgeTheme.resolve(style)
        let font = Font.system(size: size.fontSize, weight: .bold, design: .monospaced)
        let radius = (size.fontSize * 0.42).rounded()
        (Text(typed).foregroundColor(Color(nsColor: theme.text).opacity(0.4))
            + Text(String(text.dropFirst(typed.count))).foregroundColor(Color(nsColor: theme.text)))
            .font(font)
            .kerning(0.6)
            .padding(.horizontal, 4)
            .padding(.vertical, 1.5)
            .background(RoundedRectangle(cornerRadius: radius).fill(Color(nsColor: theme.fill)))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(Color(nsColor: theme.border), lineWidth: 1))
            .shadow(color: Color(nsColor: theme.shadow), radius: 1.5, y: 1)
            // Auto follows the system appearance; reading it here redraws the badge when it changes.
            .id(scheme)
    }
}

/// Hosts the setup window. A menu bar app has no Dock icon, so it must activate itself to come forward.
final class Onboarding: NSObject, NSWindowDelegate {
    static let completedKey = "onboardingCompleted"

    let model = OnboardingModel()
    private let state: AppState
    private var window: NSWindow?

    init(state: AppState) {
        self.state = state
    }

    static var isCompleted: Bool {
        UserDefaults.standard.bool(forKey: completedKey)
    }

    var isVisible: Bool { window?.isVisible ?? false }

    /// Called after Finish, so the app can show Settings or sync state.
    var onComplete: () -> Void = {}

    func show() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: OnboardingView(model: model, state: state)))
            window.title = "Set Up VimE"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.setContentSize(NSSize(width: 540, height: 460))
            self.window = window
        }
        model.trusted = Permissions.isTrusted(prompt: false)
        model.step = .welcome
        model.onFinish = { [weak self] in
            UserDefaults.standard.set(true, forKey: Self.completedKey)
            self?.window?.close()
            self?.onComplete()
        }
        state.launchAtLogin = LoginItem.isEnabled
        model.startPolling()
        if let window { Windows.present(window) }
    }

    func windowWillClose(_ notification: Notification) {
        model.stopPolling()
    }
}
