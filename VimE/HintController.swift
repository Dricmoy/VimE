import AppKit
import VimECore

/// Owns the mode, hint sessions and scrolling. All methods run on the main thread.
final class HintController {
    var isEnabled = true {
        didSet { if !isEnabled { end() } }
    }

    /// Plain keys (f, hjkl, gg, G, d, u, ?) act outside text fields; ⌥F works regardless.
    var plainKeysEnabled = true

    /// Per-app overrides of the above.
    var rules = AppRules()

    /// Fired each time labels appear; setup uses it to confirm hints work.
    var onHintsShown: (() -> Void)?

    /// ⌃⌥⌘V and ⌃⌥⌘⇧V. The app owns the settings they change.
    var onGlobalCommand: ((GlobalCommand) -> Void)?

    private var mode: Mode = .passthrough
    private var router = KeyRouter()
    private let scroller = Scroller()
    private let help = HelpPanel()
    /// Recent "user is typing" answers, so fast typing doesn't pay an Accessibility round trip per key.
    /// Only `true` is cached: a stale `true` at worst types a letter, a stale `false` would eat one.
    private var editableUntil: TimeInterval = 0
    /// Last definite answer, used when a busy app doesn't reply (e.g. while it handles a scroll burst).
    private var lastKnownFocus: (pid: pid_t, editable: Bool, at: TimeInterval)?
    private var session: HintSession?
    private var targets: [HintTarget] = []
    /// Letters typed before the tree walk finished.
    private var pending: [(Character, Click)] = []
    /// Bumped on every begin/end so a stale walk result is dropped.
    private var generation = 0
    private let overlay = Overlay()
    private let walkQueue = DispatchQueue(label: "VimE.walk", qos: .userInteractive)

    func start() {
        // Turn on Chromium/Electron trees as apps come forward, so focus checks work before the first hint.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let self else { return }
            self.editableUntil = 0
            self.lastKnownFocus = nil
            self.scroller.invalidate()
            self.help.hide()
            if self.mode == .hint { self.end() }
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                Accessibility.enableTree(for: app)
            }
        }
        if let app = NSWorkspace.shared.frontmostApplication {
            Accessibility.enableTree(for: app)
        }
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
            // Any key closes the cheat sheet; Esc does nothing else.
            help.hide()
            if input.keyCode == KeyRouter.escapeKeyCode { return true }
        }
        let front = NSWorkspace.shared.frontmostApplication
        let rule = rules.rule(for: front?.bundleIdentifier)
        if mode == .passthrough && rule == .off { return false }

        let action = router.route(input, mode: mode,
                                  plainKeysAllowed: plainKeysEnabled && rule == .normal,
                                  focusIsEditable: { self.focusIsEditable(pid: front?.processIdentifier) })
        if action != .pass { Log.keys.debug("\(input.characters, privacy: .public) -> \(String(describing: action), privacy: .public)") }
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
        case .backspace:
            session?.backspace()
            overlay.update(typed: session?.typed ?? "")
            return true
        case .type(let c, let click):
            type(c, click)
            return true
        case .scroll(let command, let isRepeat):
            guard let front, front.processIdentifier != getpid() else { return false }
            scroller.scroll(command, pid: front.processIdentifier, isRepeat: isRepeat)
            return true
        case .showHelp:
            help.show(plainKeys: plainKeysEnabled)
            return true
        }
    }

    private func focusIsEditable(pid: pid_t?) -> Bool {
        guard let pid else { return true }
        let now = ProcessInfo.processInfo.systemUptime
        if now < editableUntil { return true }
        let editable: Bool
        if let answer = Accessibility.focusIsEditable(pid: pid) {
            editable = answer
            lastKnownFocus = (pid, answer, now)
        } else if let last = lastKnownFocus, last.pid == pid, now - last.at < 3 {
            editable = last.editable
        } else {
            editable = true  // Unknown: let the key through rather than risk eating typed text.
        }
        if editable { editableUntil = now + 0.5 }
        return editable
    }

    private func begin(pid: pid_t) {
        mode = .hint
        generation += 1
        let gen = generation
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let screens = NSScreen.screens.map { Geometry.axRect(fromCocoa: $0.frame, primaryHeight: primaryHeight) }

        walkQueue.async { [weak self] in
            let started = ProcessInfo.processInfo.systemUptime
            let found = Accessibility.collectTargets(pid: pid, screens: screens)
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
                self.overlay.show(labels: labels, frames: found.map(\.frame))
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
        switch outcome {
        case .matched(let i):
            let target = targets[i]
            end()
            walkQueue.async { Accessibility.press(target, click) }
        case .narrowed:
            overlay.update(typed: session.typed)
        case .noMatch:
            break
        }
    }

    private func end() {
        mode = .passthrough
        generation += 1
        session = nil
        targets = []
        pending = []
        overlay.hide()
    }
}
