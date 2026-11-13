#if DEBUG
import AppKit
import ApplicationServices
import VimECore

/// Debug builds only: `open -n -W VimE.app --args --dump-hints <pid> <output file> [--attrs] [--activate]`
/// writes the hint targets VimE would show there, then quits. Launched with `open` so
/// macOS checks VimE's own Accessibility permission rather than the terminal's. Never starts the event
/// tap or touches settings, so it can run next to the installed VimE.
enum HintDump {
    /// `--dump-focus <pid> <output file> <seconds>`: samples the app's focused element four times a
    /// second (role, subrole, editable ancestor, how long the app took, VimE's verdict). No keys sent.
    static func runFocusIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--dump-focus"), args.count > i + 3,
              let pid = pid_t(args[i + 1]), let seconds = Double(args[i + 3]) else { return }
        let out = args[i + 2]
        if let app = NSRunningApplication(processIdentifier: pid) { Accessibility.enableTree(for: app) }
        var lines: [String] = []
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            let started = ProcessInfo.processInfo.systemUptime
            let verdict = Accessibility.focusIsEditable(pid: pid)
            let ms = Int((ProcessInfo.processInfo.systemUptime - started) * 1000)
            let front = NSWorkspace.shared.frontmostApplication?.processIdentifier == pid ? "front" : "back"
            lines.append("\(Date().timeIntervalSince1970) \(front) \(ms)ms editable=\(verdict.map(String.init) ?? "nil") "
                         + Accessibility.debugFocus(pid: pid))
            try? lines.joined(separator: "\n").write(toFile: out, atomically: true, encoding: .utf8)
            Thread.sleep(forTimeInterval: 0.25)
        }
        exit(0)
    }

    /// `--dump-pointer <output file>`: which app VimE thinks is under the pointer.
    static func runPointerIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--dump-pointer"), args.count > i + 1 else { return }
        let p = Pointer.location
        let apps = NSWorkspace.shared.runningApplications.filter { Pointer.isOverApp($0.processIdentifier, at: p) }
        let line = "pointer \(p) over: " + apps.map { "\($0.localizedName ?? "?") (\($0.processIdentifier))" }.joined(separator: ", ")
        try? line.write(toFile: args[i + 1], atomically: true, encoding: .utf8)
        exit(0)
    }

    /// `--render-badges <window.png> <dump.txt> <x> <y> <style> <size> <out.png> [typed]`: draws the real
    /// badges for a `--dump-hints` file over a screenshot of that window, whose top-left is at x,y.
    static func runRenderIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--render-badges"), args.count > i + 7,
              let shot = NSImage(contentsOfFile: args[i + 1]),
              let dump = try? String(contentsOfFile: args[i + 2], encoding: .utf8),
              let x = Double(args[i + 3]), let y = Double(args[i + 4]),
              let style = BadgeStyle(rawValue: args[i + 5]), let size = BadgeSize(rawValue: args[i + 6]) else { return }
        // The screenshot's pixels are at 2x; its point size is what the frames use.
        if let rep = shot.representations.first { shot.size = NSSize(width: rep.pixelsWide / 2, height: rep.pixelsHigh / 2) }
        var frames: [CGRect] = []
        for line in dump.split(separator: "\n") where line.hasPrefix("KEEP") {
            guard let open = line.lastIndex(of: "(") else { continue }
            let n = line[open...].split(whereSeparator: { !"0123456789-".contains($0) }).compactMap { Double($0) }
            guard n.count == 4 else { continue }
            frames.append(CGRect(x: n[0] - x, y: n[1] - y, width: n[2], height: n[3]))
        }
        let typed = args.count > i + 8 ? args[i + 8] : ""
        let rep = Overlay.render(over: shot, elements: frames, labels: Labels.make(count: frames.count), style: style,
                                 size: size, typed: typed)
        try? rep?.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: args[i + 7]))
        exit(0)
    }

    static func runIfRequested() {
        runRenderIfRequested()
        runPointerIfRequested()
        runFocusIfRequested()
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--dump-hints"), args.count > i + 2,
              let pid = pid_t(args[i + 1]) else { return }
        let out = args[i + 2]
        var lines = ["trusted: \(AXIsProcessTrusted())"]
        if let app = NSRunningApplication(processIdentifier: pid) {
            Accessibility.enableTree(for: app)
            if args.contains("--activate") { app.activate() }
            Thread.sleep(forTimeInterval: 2.5)  // Chromium builds its tree after the switch flips.
        }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let screens = NSScreen.screens.map { Geometry.axRect(fromCocoa: $0.frame, primaryHeight: primaryHeight) }

        let started = ProcessInfo.processInfo.systemUptime
        let targets = Accessibility.collectTargets(pid: pid, screens: screens)
        let ms = Int((ProcessInfo.processInfo.systemUptime - started) * 1000)
        lines.append("targets: \(targets.count) in \(ms) ms")
        for t in targets {
            let r = t.frame
            lines.append("KEEP \(Accessibility.debugRole(t.element)) \"\(Accessibility.debugName(t.element))\" "
                         + "(\(Int(r.minX)),\(Int(r.minY)) \(Int(r.width))x\(Int(r.height)))")
            if args.contains("--attrs") { lines.append("    attrs: " + Accessibility.debugAttributes(t.element)) }
        }
        try? lines.joined(separator: "\n").write(toFile: out, atomically: true, encoding: .utf8)
        exit(0)
    }
}
#endif
