import AppKit
import ApplicationServices
import VimECore

struct HintTarget {
    let element: AXUIElement
    /// Accessibility space: top-left origin of the primary display.
    let frame: CGRect
    /// A text field or similar: choosing it means the user is about to type.
    var isTextInput = false
}

/// Lets the main thread stop a tree walk that's no longer wanted (Esc, app switch).
final class WalkToken: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    var isCancelled: Bool { lock.withLock { flag } }
    func cancel() { lock.withLock { flag = true } }
}

enum Accessibility {
    private static let editableRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]
    /// Turning trees on and off for other apps. Serial, and off the main thread so a hung app
    /// can't stall the key tap. The two caches below are only touched on it.
    private static let treeQueue = DispatchQueue(label: "VimE.trees", qos: .userInitiated)
    private static var chromium: [URL: Bool] = [:]
    /// Browsers VimE switched AXEnhancedUserInterface on in, to switch it back off later.
    private static var enhanced: Set<pid_t> = []

    /// VimE's default wait for any app's Accessibility answer, set once at launch. Setting a timeout on
    /// the system-wide element changes this default for every element, so nothing else may do that.
    /// The system default is about 6 s, long enough for a hung app to freeze the key tap.
    static func configureDefaultTimeout() {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.25)
    }

    /// The app that has keyboard focus. Usually the frontmost app, but a non-activating panel
    /// (Raycast, Spotlight, Alfred, the emoji picker) takes the keyboard without becoming frontmost.
    static func focusedApp() -> NSRunningApplication? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(), kAXFocusedApplicationAttribute as CFString,
                                            &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        var pid: pid_t = 0
        guard AXUIElementGetPid(value as! AXUIElement, &pid) == .success else { return nil }
        return NSRunningApplication(processIdentifier: pid)
    }

    /// Electron and Chromium only build their web content tree when an assistive app asks.
    /// Runs in the background; returns immediately.
    static func enableTree(for app: NSRunningApplication) {
        treeQueue.async {
            let pid = app.processIdentifier
            let element = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(element, 0.2)
            AXUIElementSetAttributeValue(element, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            // Chromium browsers ignore the switch above and wait for an "enhanced" client like VoiceOver.
            // Side effect: some window managers animate this app's windows more slowly, so it's
            // switched back off when VimE pauses, the app is set Off, or VimE quits.
            if isChromiumBrowser(app), !enhanced.contains(pid) {
                AXUIElementSetAttributeValue(element, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
                enhanced.insert(pid)
            }
        }
    }

    /// Switches AXEnhancedUserInterface back off: in one browser, or in all of them when `pid` is nil.
    /// `wait` blocks until done, for quitting.
    static func releaseTrees(pid: pid_t? = nil, wait: Bool = false) {
        let work = {
            for p in enhanced where pid == nil || p == pid {
                let element = AXUIElementCreateApplication(p)
                AXUIElementSetMessagingTimeout(element, 0.2)
                AXUIElementSetAttributeValue(element, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse)
                enhanced.remove(p)
            }
        }
        if wait { treeQueue.sync(execute: work) } else { treeQueue.async(execute: work) }
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
        AXUIElementSetMessagingTimeout(element, 0.1)
        if isEditable(element) { return true }
        // Command palettes and comboboxes (aria-activedescendant) keep the caret in their text field,
        // but Chromium and Electron report the highlighted option as focused. Then ask where the caret is.
        guard Focus.shouldCheckCaret(focusAncestorRoles: ancestorRoles(element, depth: Focus.optionSearchDepth))
        else { return false }
        if let caret = caretElement(element), isEditable(caret) { return true }
        return false
    }

    /// Roles of the element's parents, nearest first.
    private static func ancestorRoles(_ e: AXUIElement, depth: Int) -> [String] {
        var roles: [String] = []
        var current = e
        for _ in 0..<depth {
            guard let up = element(current, kAXParentAttribute) else { break }
            roles.append(string(up, kAXRoleAttribute) ?? "")
            current = up
        }
        return roles
    }

    /// Moves keyboard focus from a text field to the page around it, as clicking empty page space
    /// would. Web content only: browsers and Electron apps let the page (AXWebArea) take focus. Returns
    /// false when there's no page to move to (native apps), so Esc can go to the app instead.
    static func leaveTextField(pid: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.1)
        guard var e = element(app, kAXFocusedUIElementAttribute) else { return false }
        for _ in 0..<40 {
            AXUIElementSetMessagingTimeout(e, 0.1)
            if string(e, kAXRoleAttribute) == "AXWebArea" {
                return AXUIElementSetAttributeValue(e, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success
            }
            guard let up = element(e, kAXParentAttribute) else { return false }
            e = up
        }
        return false
    }

    /// A text control, or web content inside one (contenteditable and friends report an editable ancestor).
    private static func isEditable(_ element: AXUIElement) -> Bool {
        if let role = string(element, kAXRoleAttribute), editableRoles.contains(role) { return true }
        var ancestor: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, "AXEditableAncestor" as CFString, &ancestor) == .success
    }

    /// The element holding the text caret (or the start of the selection), in web content.
    /// Nil in native apps, which don't expose text markers.
    static func caretElement(_ e: AXUIElement) -> AXUIElement? {
        var range: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, "AXSelectedTextMarkerRange" as CFString, &range) == .success,
              let range else { return nil }
        // Chromium doesn't offer AXStartTextMarkerForTextMarkerRange; the C call reads the range directly.
        guard CFGetTypeID(range) == AXTextMarkerRangeGetTypeID() else { return nil }
        let start = AXTextMarkerRangeCopyStartMarker(range as! AXTextMarkerRange)
        var owner: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(e, "AXUIElementForTextMarker" as CFString, start,
                                                         &owner) == .success,
              let owner, CFGetTypeID(owner) == AXUIElementGetTypeID() else { return nil }
        return (owner as! AXUIElement)
    }

    /// Visible clickable elements in the app's focused window and menu bar.
    /// `screens` are in accessibility space. Call off the main thread.
    /// Stops after `limit` targets, `maxVisits` elements, `budget` seconds, or when `token` is cancelled,
    /// keeping what it found so far, so huge pages and hung apps can't hold hint mode open.
    static func collectTargets(pid: pid_t, screens: [CGRect], limit: Int = 1500, maxVisits: Int = 8000,
                               budget: TimeInterval = 1.0, token: WalkToken? = nil) -> [HintTarget] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        var found: [HintTarget] = []
        var visits = 0
        let deadline = ProcessInfo.processInfo.systemUptime + budget
        func outOfBudget() -> Bool {
            visits % 64 == 0 && (ProcessInfo.processInfo.systemUptime > deadline || token?.isCancelled == true)
        }
        var stopped = false

        func walk(_ e: AXUIElement, _ context: HintRules.Context, depth: Int) {
            guard !stopped, depth < 60, found.count < limit else { return }
            visits += 1
            if visits > maxVisits || outOfBudget() {
                stopped = true
                return
            }
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
                    found.append(HintTarget(element: e, frame: shown,
                                            isTextInput: role.map(editableRoles.contains) ?? false))
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
            // No AXPress (text fields, list rows): click the visible center instead. Any other error,
            // a timeout above all, usually means the press happened (a button that opens a dialog
            // answers late), and a click on top would press it twice.
            if needsClick(AXUIElementPerformAction(target.element, kAXPressAction as CFString)) {
                mouseClick(at: point, button: .left)
            }
        case .secondary:
            if needsClick(AXUIElementPerformAction(target.element, kAXShowMenuAction as CFString)) {
                mouseClick(at: point, button: .right)
            }
        case .command:
            mouseClick(at: point, button: .left, flags: .maskCommand)
        }
    }

    private static func needsClick(_ result: AXError) -> Bool {
        result == .actionUnsupported || result == .attributeUnsupported || result == .invalidUIElement
    }

    /// A real click needs the pointer on the target, so it goes there for the click and comes back.
    private static func mouseClick(at point: CGPoint, button: CGMouseButton, flags: CGEventFlags = []) {
        let (down, up): (CGEventType, CGEventType) = button == .right ? (.rightMouseDown, .rightMouseUp)
                                                                      : (.leftMouseDown, .leftMouseUp)
        let pointer = Pointer.location
        for type in [down, up] {
            guard let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point,
                                      mouseButton: button) else { continue }
            event.flags = flags
            event.post(tap: .cghidEventTap)
        }
        Pointer.restore(to: pointer, tap: .cghidEventTap)
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

    /// The focused element and its nearest ancestors: role/subrole, plus whether it has an editable ancestor.
    static func debugFocus(pid: pid_t) -> String {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &value)
        guard err == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return "focus err \(err.rawValue)" }
        var e = value as! AXUIElement
        var ancestor: CFTypeRef?
        let editableAncestor = AXUIElementCopyAttributeValue(e, "AXEditableAncestor" as CFString, &ancestor) == .success
        var chain: [String] = []
        for _ in 0..<4 {
            chain.append("\(string(e, kAXRoleAttribute) ?? "?")/\(string(e, kAXSubroleAttribute) ?? "-")")
            guard let up = element(e, kAXParentAttribute) else { break }
            e = up
        }
        let caret = caretElement(value as! AXUIElement).map { c -> String in
            var anc: CFTypeRef?
            let ed = AXUIElementCopyAttributeValue(c, "AXEditableAncestor" as CFString, &anc) == .success
            return "\(string(c, kAXRoleAttribute) ?? "?")(editableAncestor=\(ed))"
        } ?? "none"
        return "editableAncestor=\(editableAncestor) caret=\(caret) "
            + chain.joined(separator: " < ")
    }

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
