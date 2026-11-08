#if DEBUG
import AppKit
import ApplicationServices
import VimECore

/// Debug builds only: `open -n -W VimE.app --args --dump-hints <pid> <output file> [--attrs] [--activate]`
/// writes the hint targets VimE would show there, then quits. Launched with `open` so
/// macOS checks VimE's own Accessibility permission rather than the terminal's. Never starts the event
/// tap or touches settings, so it can run next to the installed VimE.
enum HintDump {
    static func runIfRequested() {
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
