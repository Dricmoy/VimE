import AppKit
import SwiftUI

struct Shortcut: Hashable {
    let keys: String
    let action: String
}

/// The one list of keys, shown in Settings, at the end of setup and on `?`.
enum Shortcuts {
    static func anywhere(plainKeys: Bool) -> [Shortcut] {
        var list: [Shortcut] = []
        if plainKeys { list.append(Shortcut(keys: "f", action: "Show hints")) }
        list.append(Shortcut(keys: "⌥F", action: "Show hints, even in a text field"))
        if plainKeys {
            list += [
                Shortcut(keys: "j  k", action: "Scroll down / up"),
                Shortcut(keys: "h  l", action: "Scroll left / right"),
                Shortcut(keys: "d  u", action: "Half page down / up"),
                Shortcut(keys: "gg  G", action: "Top / bottom"),
                Shortcut(keys: "?", action: "Show this list"),
                Shortcut(keys: "Esc", action: "Leave a text field (web and Electron apps)"),
            ]
        }
        list += [
            Shortcut(keys: "⌃⌥⌘V", action: "Turn VimE on or off"),
            Shortcut(keys: "⌃⌥⌘⇧V", action: "This app: On, ⌥F only, Off"),
        ]
        return list
    }

    static let inHints: [Shortcut] = [
        Shortcut(keys: "a–z", action: "Type a label to click it"),
        Shortcut(keys: "⇧", action: "Hold on the last letter to right-click"),
        Shortcut(keys: "⌘", action: "Hold on the last letter to ⌘-click (new tab)"),
        Shortcut(keys: "⌫", action: "Undo a letter"),
        Shortcut(keys: "Esc", action: "Cancel"),
    ]
}

struct ShortcutRows: View {
    let shortcuts: [Shortcut]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
            ForEach(shortcuts, id: \.self) { s in
                GridRow {
                    Text(s.keys).font(.system(.body, design: .monospaced).bold())
                        .frame(minWidth: 52, alignment: .leading)
                    Text(s.action)
                }
            }
        }
    }
}

private struct HelpView: View {
    let plainKeys: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("VimE").font(.title2.bold())
                Spacer()
                Text("any key closes").font(.caption).foregroundStyle(.secondary)
            }
            Text("Outside text fields").font(.headline).foregroundStyle(.secondary)
            ShortcutRows(shortcuts: Shortcuts.anywhere(plainKeys: plainKeys))
            Text("While hints are showing").font(.headline).foregroundStyle(.secondary)
            ShortcutRows(shortcuts: Shortcuts.inHints)
        }
        .padding(24)
        .frame(width: 400)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

/// Cheat sheet over the current app. Never takes focus, so the app keeps its keys.
final class HelpPanel {
    private var panel: NSPanel?
    private var clickMonitor: Any?

    var isVisible: Bool { panel?.isVisible ?? false }

    func show(plainKeys: Bool) {
        hide()
        let host = NSHostingView(rootView: HelpView(plainKeys: plainKeys))
        let size = host.fittingSize
        let screen = NSScreen.main?.frame ?? .zero
        let panel = NSPanel(contentRect: NSRect(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2,
                                                width: size.width, height: size.height),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = host
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.orderFrontRegardless()
        self.panel = panel
        // A click anywhere closes it too.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hide()
        }
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
    }
}
