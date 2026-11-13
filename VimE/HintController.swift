import AppKit
import VimECore

/// Owns the mode, hint sessions and scrolling. All methods run on the main thread.
final class HintController {
    var isEnabled = true {
        didSet {
            guard isEnabled != oldValue else { return }
            if isEnabled {
                prepareFrontmostApp()
            } else {
                end()
                leaveInsert()
                Accessibility.releaseTrees()
            }
            refreshIndicator()
        }
    }

    /// Plain keys (f, hjkl, gg, G, d, u, ?) act outside text fields; ⌥F works regardless.
    var plainKeysEnabled = true {
        didSet { if plainKeysEnabled != oldValue { prepareFrontmostApp() } }
    }

    var badgeStyle: BadgeStyle = .auto
    var badgeSize: BadgeSize = .medium

    var indicatorPosition: IndicatorPosition {
        get { indicator.position }
        set { indicator.position = newValue; refreshIndicator() }
    }

    /// Show the indicator while typing in a text field too, not only in the `i` Insert mode.
    var indicatorWhileTyping = false {
        didSet { if indicatorWhileTyping != oldValue { prepareFrontmostApp() } }
    }

    /// Per-app overrides of the above.
    var rules = AppRules() {
        didSet { if rules != oldValue { prepareFrontmostApp() } }
    }

    /// Per-app behaviour switches (Esc leaves text fields…).
    var options = AppOptions()

    /// Fired each time labels appear; setup uses it to confirm hints work.
    var onHintsShown: (() -> Void)?

    /// ⌃⌥⌘V and ⌃⌥⌘⇧V. The app owns the settings they change.
    var onGlobalCommand: ((GlobalCommand) -> Void)?

    private var mode: Mode = .passthrough
    private var router = KeyRouter()
    private let scroller = Scroller()
    private let help = HelpPanel()
    private let indicator = ModeIndicator()
    private let focusTracker = FocusTracker()
    /// What the focus tracker last saw in the frontmost app.
    private var typing = false
    /// Recent "user is typing" answers, so fast typing doesn't pay an Accessibility round trip per key.
    /// Only `true` is cached: a stale `true` at worst types a letter, a stale `false` would eat one.
    private var editableUntil: TimeInterval = 0
    /// Last definite answer, used only for held-down keys when a busy app doesn't reply (an app
    /// handling a scroll burst). A fresh press with no answer is let through instead.
    private var lastKnownFocus: (pid: pid_t, editable: Bool, at: TimeInterval)?
    private var session: HintSession?
    private var targets: [HintTarget] = []
    /// Letters typed before the tree walk finished.
    private var pending: [(Character, Click)] = []
    /// Bumped on every begin/end so a stale walk result is dropped.
    private var generation = 0
    private var walkToken: WalkToken?
    private let overlay = Overlay()
    private let walkQueue = DispatchQueue(label: "VimE.walk", qos: .userInteractive)
    /// Separate from the walk, so a press never waits behind a slow walk.
    private let pressQueue = DispatchQueue(label: "VimE.press", qos: .userInteractive)
    private var mouseMonitor: Any?
    private var hintStartedAt: TimeInterval = 0
    /// ⇧ or ⌘ held on any letter of a label, not just the last, picks the click.
    private var labelClick: Click = .primary

    func start() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.forgetFocus()
            self.router.clearPending()
            self.scroller.invalidate()
            self.help.hide()
            if self.mode == .hint { self.end() }
            // Insert mode belongs to the app it was turned on in.
            self.leaveInsert()
            self.prepareFrontmostApp()
        }
        // Clicks move focus without a key press, and any click or scroll means the hints are stale.
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
        ) { [weak self] event in
            guard let self else { return }
            if event.type == .scrollWheel {
                // Trackpad momentum from a scroll just before ⌥F isn't the user moving on.
                guard event.momentumPhase.isEmpty,
                      ProcessInfo.processInfo.systemUptime - self.hintStartedAt > 0.3 else { return }
            } else {
                self.forgetFocus()
                // A click may have moved focus into or out of a text field.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self.focusTracker.check() }
            }
            if self.mode == .hint { self.end() }
        }
        focusTracker.onChange = { [weak self] editable in
            self?.typing = editable
            self?.refreshIndicator()
        }
        prepareFrontmostApp()
    }

    /// Turns on Chromium/Electron trees in the frontmost app so focus checks work before the first hint,
    /// or turns the browser switch back off if VimE is paused or the app is set Off.
    private func prepareFrontmostApp() {
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != getpid() else { return }
        let rule = rules.rule(for: app.bundleIdentifier)
        if isEnabled && rule != .off {
            Accessibility.enableTree(for: app)
        } else {
            Accessibility.releaseTrees(pid: app.processIdentifier)
        }
        // Typing only changes what plain keys do, so follow focus only where they work.
        typing = false
        let follow = isEnabled && indicatorWhileTyping && indicator.position != .hidden && plainKeysEnabled
            && rule == .normal
        focusTracker.track(follow ? app.processIdentifier : nil)
        refreshIndicator()
    }

    private func refreshIndicator() {
        if !isEnabled {
            indicator.show(.hidden)
        } else if mode == .insert {
            indicator.show(.insert)
        } else if typing && indicatorWhileTyping {
            indicator.show(.typing)
        } else {
            indicator.show(.hidden)
        }
    }

    private func leaveInsert() {
        guard mode == .insert else { return }
        mode = .passthrough
        refreshIndicator()
    }

    private func forgetFocus() {
        editableUntil = 0
        lastKnownFocus = nil
    }

    /// Returns true to swallow the key.
    func handle(_ input: KeyInput) -> Bool {
        // Before the enabled check, so the shortcut can turn VimE back on.
        if let command = KeyRouter.globalCommand(input) {
            if !input.isRepeat { onGlobalCommand?(command) }
            return true
        }
        guard isEnabled else { return false }
        if help.isVisible {
            // Any key just closes the cheat sheet.
            help.hide()
            return true
        }
        // Insert mode passes everything but Esc, without asking anything of the app.
        if mode == .insert {
            guard router.route(input, mode: .insert, plainKeysAllowed: false, focusIsEditable: { true }) == .exitInsert
            else { return false }
            leaveInsert()
            return true
        }
        if mode == .passthrough && !KeyRouter.mightAct(input) {
            router.clearPending()
            return false
        }
        // The app with keyboard focus, which isn't the frontmost app while a panel like Raycast,
        // Spotlight or Alfred is open over it.
        let front = Accessibility.focusedApp() ?? NSWorkspace.shared.frontmostApplication
        let rule = rules.rule(for: front?.bundleIdentifier)
        if mode == .passthrough && rule == .off { return false }

        let action = router.route(input, mode: mode,
                                  plainKeysAllowed: plainKeysEnabled && rule == .normal,
                                  escLeavesTextField: options.value(.escLeavesTextField, for: front?.bundleIdentifier),
                                  now: ProcessInfo.processInfo.systemUptime,
                                  focusIsEditable: { self.focusIsEditable(pid: front?.processIdentifier,
                                                                          isRepeat: input.isRepeat) })
        // The action kind only: never the typed character.
        if action != .pass {
            let kind = String(describing: action).prefix { $0 != "(" }
            Log.keys.debug("key -> \(kind, privacy: .public)")
        }
        switch action {
        case .pass:
            return false
        case .swallow:
            return true
        case .enterHint:
            guard let front, front.processIdentifier != getpid() else { return false }
            begin(pid: front.processIdentifier)
            return true
        case .exitHint:
            end()
            return true
        case .exitHintAndPass:
            end()
            return false
        case .enterInsert:
            end()
            mode = .insert
            refreshIndicator()
            return true
        case .exitInsert:
            leaveInsert()
            return true
        case .leaveTextField:
            guard let front else { return false }
            forgetFocus()
            // Swallowed only if focus actually moved; otherwise the app gets its Esc.
            let left = Accessibility.leaveTextField(pid: front.processIdentifier)
            if left { focusTracker.check() }
            return left
        case .backspace:
            if session == nil {
                _ = pending.popLast()
            } else {
                session?.backspace()
                overlay.update(typed: session?.typed ?? "")
            }
            return true
        case .type(let c, let click):
            // ⌘ plus a letter that continues no label is a shortcut for the app (⌘W, ⌘Q, ⌘C…).
            if click == .command, let session, !KeyRouter.commandMeansClick(c, session: session) {
                end()
                return false
            }
            type(c, click)
            return true
        case .scroll(let command, let isRepeat):
            guard let front, front.processIdentifier != getpid() else { return false }
            scroller.scroll(command, pid: front.processIdentifier, isRepeat: isRepeat, keyCode: input.keyCode)
            return true
        case .showHelp:
            help.show(plainKeys: plainKeysEnabled)
            return true
        }
    }

    private func focusIsEditable(pid: pid_t?, isRepeat: Bool) -> Bool {
        guard let pid else { return true }
        let now = ProcessInfo.processInfo.systemUptime
        if now < editableUntil { return true }
        let editable: Bool
        if let answer = Accessibility.focusIsEditable(pid: pid) {
            editable = answer
            lastKnownFocus = (pid, answer, now)
        } else if isRepeat, let last = lastKnownFocus, last.pid == pid, now - last.at < 3 {
            editable = last.editable
        } else {
            editable = true  // Unknown: let the key through rather than risk eating typed text.
        }
        if editable { editableUntil = now + 0.5 }
        return editable
    }

    private func begin(pid: pid_t) {
        mode = .hint
        hintStartedAt = ProcessInfo.processInfo.systemUptime
        generation += 1
        let gen = generation
        let token = WalkToken()
        walkToken = token
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let screens = NSScreen.screens.map { Geometry.axRect(fromCocoa: $0.frame, primaryHeight: primaryHeight) }

        walkQueue.async { [weak self] in
            let started = ProcessInfo.processInfo.systemUptime
            let found = Accessibility.collectTargets(pid: pid, screens: screens, token: token)
            let ms = Int((ProcessInfo.processInfo.systemUptime - started) * 1000)
            Log.keys.debug("hints: \(found.count) targets in \(ms) ms")
            DispatchQueue.main.async {
                guard let self, gen == self.generation else { return }
                guard !found.isEmpty else {
                    NSSound.beep()
                    self.end()
                    return
                }
                let labels = Labels.make(count: found.count)
                self.targets = found
                self.session = HintSession(labels: labels)
                self.overlay.show(labels: labels, frames: found.map(\.frame), style: self.badgeStyle,
                                  size: self.badgeSize)
                self.onHintsShown?()
                let buffered = self.pending
                self.pending = []
                buffered.forEach { self.type($0.0, $0.1) }
            }
        }
    }

    private func type(_ c: Character, _ click: Click) {
        guard var session else {
            pending.append((c, click))
            return
        }
        let outcome = session.type(c)
        self.session = session
        if outcome != .noMatch, click != .primary { labelClick = click }
        switch outcome {
        case .matched(let i):
            let target = targets[i]
            let click = labelClick
            end()
            // Typing straight after choosing a text field must reach it, even before focus has moved.
            if target.isTextInput { editableUntil = ProcessInfo.processInfo.systemUptime + 1 }
            pressQueue.async { Accessibility.press(target, click) }
        case .narrowed:
            overlay.update(typed: session.typed)
        case .noMatch:
            break
        }
    }

    private func end() {
        if mode == .hint { mode = .passthrough }
        generation += 1
        walkToken?.cancel()
        walkToken = nil
        session = nil
        targets = []
        pending = []
        labelClick = .primary
        overlay.hide()
    }
}
