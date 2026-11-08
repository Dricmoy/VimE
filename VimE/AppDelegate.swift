import AppKit
import VimECore

@main
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let state = AppState()
    private let controller = HintController()
    private var tap: EventTap?
    private var permissionTimer: Timer?
    private lazy var onboarding = Onboarding(state: state)
    private let settings = SettingsWindow()
    private let toast = Toast()
    /// The app the menu bar's per-app switch applies to: the frontmost app other than VimE.
    private var currentApp: NSRunningApplication?

    static func main() {
        #if DEBUG
        HintDump.runIfRequested()
        #endif
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(delegate.state.showInDock ? .regular : .accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = Self.statusImage()
        statusItem.button?.toolTip = "VimE"
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        NSApp.mainMenu = makeMainMenu()

        trackCurrentApp()

        applyState()
        state.onChange = { [weak self] in self?.applyState() }
        controller.start()
        controller.onHintsShown = { [weak self] in self?.onboarding.model.triedHint = true }
        controller.onGlobalCommand = { [weak self] in self?.run($0) }
        onboarding.onComplete = { [weak self] in self?.state.launchAtLogin = LoginItem.isEnabled }

        if Permissions.isTrusted(prompt: false) {
            startTap()
        } else {
            // Poll until the user flips the switch in System Settings.
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
                guard Permissions.isTrusted(prompt: false) else { return }
                t.invalidate()
                self?.state.trusted = true
                self?.startTap()
            }
        }

        if !Onboarding.isCompleted || !Permissions.isTrusted(prompt: false) {
            onboarding.show()
        } else if !launchedAtLogin() {
            // Opened by hand from Spotlight or Applications: show Settings, like a regular app.
            showSettings()
        }
    }

    /// Pushes preferences into the running app.
    private func applyState() {
        controller.isEnabled = state.enabled
        controller.plainKeysEnabled = state.bareKeys
        controller.rules = state.appRules
        statusItem.isVisible = state.showMenuBarIcon
        statusItem.button?.appearsDisabled = !state.enabled

        let policy: NSApplication.ActivationPolicy = state.showInDock ? .regular : .accessory
        if NSApp.activationPolicy() != policy {
            NSApp.setActivationPolicy(policy)
            // Changing policy deactivates the app; keep any open window (setup, Settings) in front.
            for window in NSApp.windows where window.isVisible { window.orderFrontRegardless() }
            NSApp.activate()
        }
    }

    /// App menu for when VimE has a window or Dock icon: ⌘, ⌘W ⌘Q and friends.
    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About VimE", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        let settingsItem = appMenu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        let setupItem = appMenu.addItem(withTitle: "Run Setup…", action: #selector(showSetup), keyEquivalent: "")
        setupItem.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide VimE", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit VimE", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)),
                           keyEquivalent: "m")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        return main
    }

    /// Opening VimE again while it runs (Spotlight, Dock, Finder) brings up Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if onboarding.isVisible { onboarding.show() } else { showSettings() }
        return false
    }

    private func launchedAtLogin() -> Bool {
        let event = NSAppleEventManager.shared().currentAppleEvent
        return event?.eventID == kAEOpenApplication
            && event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }

    private func startTap() {
        let tap = EventTap { [weak self] input in self?.controller.handle(input) ?? false }
        if tap.start() {
            self.tap = tap
            state.tapRunning = true
        } else {
            NSLog("VimE: could not create event tap")
        }
    }

    private func trackCurrentApp() {
        let mine = Bundle.main.bundleIdentifier
        if let front = NSWorkspace.shared.frontmostApplication, front.bundleIdentifier != mine { currentApp = front }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier != mine else { return }
            self?.currentApp = app
        }
    }

    /// Built each time it opens, so the per-app switch names the app you're in.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let status: String
        let rule = currentApp?.bundleIdentifier.map(state.appRules.rule(for:)) ?? state.appRules.fallback
        if tap == nil {
            status = "Waiting for Accessibility permission"
        } else if !state.enabled {
            status = "Paused"
        } else if rule == .off {
            status = "Off in this app"
        } else {
            status = state.bareKeys && rule == .normal ? "Active — f for hints, ? for keys" : "Active — ⌥F for hints"
        }
        menu.addItem(NSMenuItem(title: status, action: nil, keyEquivalent: ""))
        menu.addItem(.separator())

        // The key equivalents only label the items; the event tap handles the shortcuts.
        let toggle = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "v")
        toggle.keyEquivalentModifierMask = [.control, .option, .command]
        toggle.target = self
        toggle.state = state.enabled ? .on : .off
        menu.addItem(toggle)

        if let app = currentApp, let id = app.bundleIdentifier {
            menu.addItem(.separator())
            menu.addItem(NSMenuItem(title: "In \(app.localizedName ?? id)", action: nil, keyEquivalent: ""))
            let current = state.appRules.rule(for: id)
            for rule in AppRule.allCases {
                let item = NSMenuItem(title: rule.title, action: #selector(setRule(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = [id, rule.rawValue]
                item.state = rule == current ? .on : .off
                item.indentationLevel = 1
                item.toolTip = rule.detail
                menu.addItem(item)
            }
        }
        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let setup = NSMenuItem(title: "Run Setup…", action: #selector(showSetup), keyEquivalent: "")
        setup.target = self
        menu.addItem(setup)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit VimE", action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
    }

    /// ⌃⌥⌘V and ⌃⌥⌘⇧V, with a toast so you know where you ended up.
    private func run(_ command: GlobalCommand) {
        switch command {
        case .toggleEnabled:
            state.enabled.toggle()
            toast.show(state.enabled ? "VimE on" : "VimE paused",
                       detail: state.enabled ? nil : "⌃⌥⌘V to turn it back on")
        case .cycleAppRule:
            guard let app = currentApp, let id = app.bundleIdentifier else { return }
            let rule = state.appRules.cycle(id)
            toast.show("\(app.localizedName ?? id): \(rule.title)",
                       detail: state.enabled ? rule.detail : "VimE is paused everywhere")
        }
    }

    @objc private func setRule(_ sender: NSMenuItem) {
        guard let pair = sender.representedObject as? [String], pair.count == 2,
              let rule = AppRule(rawValue: pair[1]) else { return }
        state.appRules.set(rule, for: pair[0])
    }

    /// A hint badge with an F cut out; a template, so it follows the menu bar's light/dark look.
    private static func statusImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 16), flipped: false) { rect in
            guard let cg = NSGraphicsContext.current?.cgContext else { return false }
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 1.5, dy: 1.5), xRadius: 4, yRadius: 4).fill()
            cg.setBlendMode(.destinationOut)
            let text = NSAttributedString(string: "F", attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 11.5, weight: .black),
                .foregroundColor: NSColor.black,
            ])
            let size = text.size()
            text.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2 + 0.5))
            return true
        }
        image.isTemplate = true
        return image
    }

    @objc private func toggleEnabled() {
        state.enabled.toggle()
    }

    @objc private func showSettings() {
        settings.show(state: state) { [weak self] in
            self?.settings.close()
            self?.onboarding.show()
        }
    }

    @objc private func showSetup() {
        onboarding.show()
    }
}
