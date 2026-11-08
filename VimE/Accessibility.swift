import AppKit
import ApplicationServices
import VimECore

struct HintTarget {
    let element: AXUIElement
    /// Accessibility space: top-left origin of the primary display.
    let frame: CGRect
}

enum Accessibility {
    private static let editableRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]
    /// Main thread only.
    private static var chromium: [URL: Bool] = [:]

    /// Electron and Chromium only build their web content tree when an assistive app asks.
    static func enableTree(for app: NSRunningApplication) {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetAttributeValue(element, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        // Chromium browsers ignore the switch above and wait for an "enhanced" client like VoiceOver.
        // Side effect: some window managers animate this app's windows more slowly.
        if isChromiumBrowser(app) {
            AXUIElementSetAttributeValue(element, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        }
    }

    private static func isChromiumBrowser(_ app: NSRunningApplication) -> Bool {
        guard let url = app.bundleURL else { return false }
        if let known = chromium[url] { return known }
        let frameworks = (try? FileManager.default.contentsOfDirectory(
            atPath: url.appendingPathComponent("Contents/Frameworks").path)) ?? []
        let result = Policy.isChromiumBrowser(bundleID: app.bundleIdentifier, frameworks: frameworks)
        chromium[url] = result
        return result
    }

    /// Whether the user is typing; nil when the app didn't answer (busy, or no Accessibility support).
    /// Asks the app itself: the system-wide focused element fails with "cannot complete" in some
    /// apps (Finder among them).
    static func focusIsEditable(pid: pid_t) -> Bool? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.1)
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &value)
        if err == .noValue { return false }
        guard err == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            Log.keys.debug("focus query failed: \(err.rawValue)")
            return nil
        }
        let element = value as! AXUIElement
        if let role = string(element, kAXRoleAttribute), editableRoles.contains(role) { return true }
        // Web content: contenteditable and friends report an editable ancestor.
        var ancestor: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, "AXEditableAncestor" as CFString, &ancestor) == .success
    }

    /// Visible clickable elements in the app's focused window and menu bar.
    /// `screens` are in accessibility space. Call off the main thread.
    static func collectTargets(pid: pid_t, screens: [CGRect], limit: Int = 1500) -> [HintTarget] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        var found: [HintTarget] = []

        func walk(_ e: AXUIElement, _ context: HintRules.Context, depth: Int) {
            guard depth < 60, found.count < limit else { return }
            let (role, frame, children, enabled) = basics(e)
            let hasFrame = frame.map { $0.width > 0 && $0.height > 0 } ?? false
            if HintRules.isHidden(role: role, hasFrame: hasFrame) { return }
            var visible: CGRect?
            // Elements without a usable frame (some containers) are walked through, not judged.
            if let frame, hasFrame {
                // Hidden (scrolled away, clipped, offscreen): skip the whole subtree.
                guard let shown = HintRules.visibleRect(role: role, frame: frame, context: context),
                      screens.contains(where: { $0.intersects(shown) }) else { return }
                visible = shown
                let isTarget: Bool
                switch HintRules.decide(role: role, visible: shown, enabled: enabled, context: context) {
                case .target: isTarget = true
                case .notTarget: isTarget = false
                case .ifPressable: isTarget = canPress(e)
                }
                if isTarget {
                    found.append(HintTarget(element: e, frame: shown))
                    if HintRules.isLeaf(role: role, visible: shown) { return }
                }
            }
            let next = HintRules.childContext(role: role, visible: visible, context: context)
            for child in children { walk(child, next, depth: depth + 1) }
        }

        let windows = element(app, kAXFocusedWindowAttribute).map { [$0] } ?? elements(app, kAXWindowsAttribute)
        for window in windows {
            let frame = basics(window).1 ?? .infinite
            let area = frame.isInfinite ? screens.map { $0.width * $0.height }.reduce(0, +) : frame.width * frame.height
            walk(window, HintRules.Context(clip: frame, rootArea: area), depth: 0)
        }
        // Menus open below the bar, so the bar doesn't clip. Its items stay in the tree while the bar
        // is auto-hidden, so ask the window server whether the bar is actually showing.
        if let menuBar = element(app, kAXMenuBarAttribute) {
            let bars = shownMenuBars()
            let before = found.count
            walk(menuBar, HintRules.Context(clip: .infinite, rootArea: .greatestFiniteMagnitude), depth: 0)
            let fromBar = found[before...].filter { target in
                // Items of an open menu hang below the bar; only the bar's own items can be hidden with it.
                string(target.element, kAXRoleAttribute) != "AXMenuBarItem"
                    || Visibility.isMenuBarItemShown(target.frame, shownBars: bars)
            }
            found.removeSubrange(before...)
            found += fromBar
        }

        let kept = Geometry.dedupe(found.map(\.frame))
        return kept.map { found[$0] }
    }

    /// Where the window server is drawing menu bars right now, one per display, in accessibility space.
    /// An auto-hidden bar's window sits just above the top of its screen.
    private static func shownMenuBars() -> [CGRect] {
        guard let windows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]]
        else { return [] }
        let level = Int(CGWindowLevelForKey(.mainMenuWindow))
        return windows.compactMap { w in
            guard w[kCGWindowLayer as String] as? Int == level,
                  w[kCGWindowOwnerName as String] as? String == "Window Server",
                  let bounds = w[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds) else { return nil }
            return rect
        }
    }

    /// Where to scroll in the app's focused window: its largest scroll area (the main content
    /// in most apps), else the whole window. Accessibility space. Call off the main thread.
    static func scrollRect(pid: pid_t) -> CGRect? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.2)
        guard let window = element(app, kAXFocusedWindowAttribute),
              let windowFrame = basics(window).1 else { return nil }

        let scrollRoles: Set<String> = ["AXScrollArea", "AXWebArea"]
        // Big subtrees that never contain the main scroll area.
        let skipChildren: Set<String> = ["AXWebArea", "AXTable", "AXOutline", "AXList", "AXTextArea"]
        var best: CGRect?
        var visited = 0

        func walk(_ e: AXUIElement, depth: Int) {
            guard depth < 30, visited < 2000 else { return }
            visited += 1
            let (role, frame, children, _) = basics(e)
            if let frame {
                let clipped = frame.intersection(windowFrame)
                guard !clipped.isNull, !clipped.isEmpty else { return }
                if let role, scrollRoles.contains(role),
                   clipped.width * clipped.height > (best.map { $0.width * $0.height } ?? 0) {
                    best = clipped
                }
            }
            if let role, skipChildren.contains(role) { return }
            for child in children { walk(child, depth: depth + 1) }
        }
        walk(window, depth: 0)
        return best ?? windowFrame
    }

    /// Clicks a hint's element the way the user asked. Call off the main thread.
    static func press(_ target: HintTarget, _ click: Click) {
        let point = CGPoint(x: target.frame.midX, y: target.frame.midY)
        switch click {
        case .primary:
            if AXUIElementPerformAction(target.element, kAXPressAction as CFString) == .success { return }
            // No AXPress (text fields, list rows): click the visible center instead.
            mouseClick(at: point, button: .left)
        case .secondary:
            if AXUIElementPerformAction(target.element, kAXShowMenuAction as CFString) == .success { return }
            mouseClick(at: point, button: .right)
        case .command:
            mouseClick(at: point, button: .left, flags: .maskCommand)
        }
    }

    private static func mouseClick(at point: CGPoint, button: CGMouseButton, flags: CGEventFlags = []) {
        let (down, up): (CGEventType, CGEventType) = button == .right ? (.rightMouseDown, .rightMouseUp)
                                                                      : (.leftMouseDown, .leftMouseUp)
        for type in [down, up] {
            guard let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point,
                                      mouseButton: button) else { continue }
            event.flags = flags
            event.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Attribute helpers

    #if DEBUG
    static func debugAttributes(_ e: AXUIElement) -> String {
        var names: CFArray?
        guard AXUIElementCopyAttributeNames(e, &names) == .success, let list = names as? [String] else { return "" }
        return list.sorted().map { name -> String in
            var v: CFTypeRef?
            guard AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success, let v else { return name + "=∅" }
            if CFGetTypeID(v) == AXUIElementGetTypeID() { return name + "=<el>" }
            if let a = v as? [AnyObject] { return name + "=[\(a.count)]" }
            return name + "=" + String(String(describing: v).replacingOccurrences(of: "\n", with: " ").prefix(60))
        }.joined(separator: " | ")
    }

    static func debugRole(_ e: AXUIElement) -> String { string(e, kAXRoleAttribute) ?? "?" }

    /// Title, description or value, for debug output.
    static func debugName(_ e: AXUIElement) -> String {
        for attr in [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute] {
            if let s = string(e, attr), !s.isEmpty { return String(s.prefix(40)) }
        }
        return ""
    }
    #endif

    private static func canPress(_ e: AXUIElement) -> Bool {
        var names: CFArray?
        guard AXUIElementCopyActionNames(e, &names) == .success, let actions = names as? [String] else {
            return false
        }
        return actions.contains(kAXPressAction as String)
    }

    /// Role, frame, children and whether it's enabled, in one round trip.
    private static func basics(_ e: AXUIElement) -> (String?, CGRect?, [AXUIElement], Bool) {
        let names = [kAXRoleAttribute, kAXPositionAttribute, kAXSizeAttribute, kAXChildrenAttribute,
                     kAXEnabledAttribute] as CFArray
        var values: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(e, names, AXCopyMultipleAttributeOptions(rawValue: 0),
                                                     &values) == .success,
              let v = values as? [AnyObject], v.count == 5
        else { return (nil, nil, [], true) }

        let role = v[0] as? String
        var frame: CGRect?
        if let p = axValue(v[1], .cgPoint), let s = axValue(v[2], .cgSize) {
            var origin = CGPoint.zero, size = CGSize.zero
            if AXValueGetValue(p, .cgPoint, &origin), AXValueGetValue(s, .cgSize, &size) {
                frame = CGRect(origin: origin, size: size)
            }
        }
        let children = (v[3] as? [AnyObject] ?? []).compactMap(asElement)
        // Most elements don't report it; only an explicit "no" counts.
        let enabled = (v[4] as? Bool) ?? true
        return (role, frame, children, enabled)
    }

    private static func axValue(_ obj: AnyObject, _ type: AXValueType) -> AXValue? {
        guard CFGetTypeID(obj) == AXValueGetTypeID() else { return nil }
        let value = obj as! AXValue
        return AXValueGetType(value) == type ? value : nil
    }

    private static func asElement(_ obj: AnyObject) -> AXUIElement? {
        CFGetTypeID(obj) == AXUIElementGetTypeID() ? (obj as! AXUIElement) : nil
    }

    private static func string(_ e: AXUIElement, _ attr: String) -> String? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, attr as CFString, &v) == .success else { return nil }
        return v as? String
    }

    private static func element(_ e: AXUIElement, _ attr: String) -> AXUIElement? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, attr as CFString, &v) == .success, let v else { return nil }
        return asElement(v)
    }

    private static func elements(_ e: AXUIElement, _ attr: String) -> [AXUIElement] {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, attr as CFString, &v) == .success,
              let arr = v as? [AnyObject] else { return [] }
        return arr.compactMap(asElement)
    }
}
