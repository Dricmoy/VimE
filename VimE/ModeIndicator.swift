import AppKit
import SwiftUI
import VimECore

/// A small "-- INSERT --" label in a corner of the screen, like Vim's mode line. Never takes focus or clicks.
final class ModeIndicator {
    enum State: Equatable {
        case hidden
        /// The `i` Insert mode: every key goes to the app until Esc.
        case insert
        /// Typing in a text field, so plain keys go to the app.
        case typing
    }

    var position: IndicatorPosition = .bottomRight {
        didSet { if position != oldValue { place() } }
    }
    private var panel: NSPanel?
    private var state: State = .hidden

    func show(_ new: State) {
        guard new != state else { return }
        state = new
        guard new != .hidden, position != .hidden else {
            panel?.orderOut(nil)
            panel = nil
            return
        }
        let host = NSHostingView(rootView: IndicatorView(state: new))
        let panel = self.panel ?? Self.makePanel()
        panel.contentView = host
        panel.setContentSize(host.fittingSize)
        self.panel = panel
        place()
        panel.orderFrontRegardless()
    }

    /// The corner of the screen the pointer is on, inside the menu bar and Dock.
    private func place() {
        guard let panel else { return }
        if position == .hidden {
            panel.orderOut(nil)
            self.panel = nil
            return
        }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let area = screen?.visibleFrame ?? .zero
        let size = panel.frame.size
        let margin: CGFloat = 12
        let left = area.minX + margin, right = area.maxX - margin - size.width
        let top = area.maxY - margin - size.height, bottom = area.minY + margin
        let origin: NSPoint
        switch position {
        case .topLeft: origin = NSPoint(x: left, y: top)
        case .topRight: origin = NSPoint(x: right, y: top)
        case .bottomLeft: origin = NSPoint(x: left, y: bottom)
        case .bottomRight, .hidden: origin = NSPoint(x: right, y: bottom)
        }
        panel.setFrameOrigin(origin)
    }

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
                            defer: false)
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        return panel
    }
}

private struct IndicatorView: View {
    let state: ModeIndicator.State

    var body: some View {
        HStack(spacing: 6) {
            Text("-- INSERT --").font(.system(size: 12, weight: .bold, design: .monospaced))
            if state == .insert {
                Text("Esc to leave").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .opacity(state == .typing ? 0.7 : 1)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))
        .fixedSize()
    }
}

/// Follows keyboard focus in one app through Accessibility notifications, and reports whether you're in a
/// text field. Used only for the indicator: key handling still asks on each key, which is always current.
final class FocusTracker {
    /// Main thread: whether the focus is somewhere you type.
    var onChange: (Bool) -> Void = { _ in }

    private let queue = DispatchQueue(label: "VimE.focus", qos: .userInitiated)
    private var observer: AXObserver?
    private var pid: pid_t = 0
    /// Bumped on every request, so a slow answer for an older focus is dropped.
    private var generation = 0

    /// Starts following `pid`, or stops with nil.
    func track(_ pid: pid_t?) {
        stop()
        guard let pid else { return }
        self.pid = pid
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        queue.async { [weak self] in
            var observer: AXObserver?
            let callback: AXObserverCallback = { _, _, _, refcon in
                guard let refcon else { return }
                let tracker = Unmanaged<FocusTracker>.fromOpaque(refcon).takeUnretainedValue()
                DispatchQueue.main.async { tracker.check() }
            }
            guard AXObserverCreate(pid, callback, &observer) == .success, let observer else { return }
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 0.25)
            guard AXObserverAddNotification(observer, app, kAXFocusedUIElementChangedNotification as CFString,
                                            refcon) == .success else { return }
            DispatchQueue.main.async {
                guard let self, self.pid == pid else { return }
                CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
                self.observer = observer
            }
        }
        check()
    }

    func stop() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil
        pid = 0
        generation += 1
    }

    /// Asks again now, e.g. after a click.
    func check() {
        guard pid != 0 else { return }
        generation += 1
        let gen = generation, pid = pid
        queue.async { [weak self] in
            let editable = Accessibility.focusIsEditable(pid: pid) ?? false
            DispatchQueue.main.async {
                guard let self, gen == self.generation else { return }
                self.onChange(editable)
            }
        }
    }
}

/// Recognises games from their bundles, so they start Off. Main thread only.
enum GameDetector {
    private static var cache: [String: Bool] = [:]

    static func isGame(_ app: NSRunningApplication) -> Bool {
        guard let id = app.bundleIdentifier, let url = app.bundleURL else { return false }
        if let known = cache[id] { return known }
        let info = Bundle(url: url)?.infoDictionary ?? [:]
        let frameworks = (try? FileManager.default.contentsOfDirectory(
            atPath: url.appendingPathComponent("Contents/Frameworks").path)) ?? []
        let result = Policy.isGame(bundleID: id, category: info["LSApplicationCategoryType"] as? String,
                                   supportsGameMode: info["LSSupportsGameMode"] as? Bool ?? false,
                                   path: url.path, frameworks: frameworks)
        cache[id] = result
        return result
    }
}
