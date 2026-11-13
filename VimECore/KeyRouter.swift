import Foundation

/// A key press as seen by the event tap, reduced to what routing needs.
public struct KeyInput: Equatable {
    public var keyCode: UInt16
    /// Characters ignoring modifiers except Shift, so ⌥F reads as "f" and ⇧G as "G".
    public var characters: String
    public var command = false
    public var option = false
    public var control = false
    public var shift = false
    public var isRepeat = false

    public init(keyCode: UInt16, characters: String, command: Bool = false, option: Bool = false,
                control: Bool = false, shift: Bool = false, isRepeat: Bool = false) {
        self.keyCode = keyCode
        self.characters = characters
        self.command = command
        self.option = option
        self.control = control
        self.shift = shift
        self.isRepeat = isRepeat
    }
}

public enum Mode: Equatable {
    case passthrough
    case hint
    /// Entered with `i`: every key goes to the app until Esc, for apps where VimE can't tell you're
    /// typing (canvas apps, remote desktops, some games).
    case insert
}

/// How a hint clicks its element, picked by the modifier held on the label's last letter.
public enum Click: Equatable {
    case primary
    /// ⇧: right-click, for the context menu.
    case secondary
    /// ⌘: ⌘-click, which opens links in a new tab.
    case command
}

public enum KeyAction: Equatable {
    case pass
    case swallow
    case enterHint
    case exitHint
    /// Leave hint mode and let the key reach the app (⌘Tab, ⌘W…).
    case exitHintAndPass
    /// Esc in a text field: move focus out of it, so plain keys work again.
    case leaveTextField
    case enterInsert
    case exitInsert
    case backspace
    case type(Character, Click)
    case scroll(ScrollCommand, isRepeat: Bool)
    case showHelp
}

/// Shortcuts that work in every state: while VimE is paused, in apps set to Off, and during hints.
public enum GlobalCommand: Equatable {
    /// ⌃⌥⌘V: VimE on or off everywhere.
    case toggleEnabled
    /// ⌃⌥⌘⇧V: the frontmost app's rule, On → ⌥F only → Off.
    case cycleAppRule
}

/// Decides what each key press does. The caller owns the mode; the router only
/// remembers a pending `g` so `gg` works.
public struct KeyRouter {
    public static let fKeyCode: UInt16 = 3
    public static let escapeKeyCode: UInt16 = 53
    public static let deleteKeyCode: UInt16 = 51
    public static let vKeyCode: UInt16 = 9

    /// Plain keys VimE acts on outside text fields.
    public static let plainKeys: Set<String> = ["f", "h", "j", "k", "l", "d", "u", "g", "G", "?", "i"]

    public private(set) var pendingG = false
    private var pendingGAt: TimeInterval = 0
    /// The second `g` must follow within this many seconds, as in Vimium.
    public static let gTimeout: TimeInterval = 1

    public init() {}

    /// Whether VimE could act on this key outside hint mode: ⌥F, or an unmodified plain key.
    /// Everything else (ordinary typing, shortcuts) passes straight through without any
    /// Accessibility calls.
    public static func mightAct(_ k: KeyInput) -> Bool {
        if k.option && !k.command && !k.control && k.keyCode == fKeyCode { return true }
        if k.keyCode == escapeKeyCode && !k.option && !k.command && !k.control && !k.shift { return true }
        return !k.option && !k.command && !k.control && plainKeys.contains(k.characters)
    }

    /// Forgets a pending `g`, for keys handled without routing.
    public mutating func clearPending() {
        pendingG = false
    }

    /// Whether a `⌘`-letter in hint mode means "⌘-click this label" rather than a shortcut for the app:
    /// only when the letter continues a label and isn't a standard app shortcut.
    public static func commandMeansClick(_ c: Character, session: HintSession) -> Bool {
        !appShortcutLetters.contains(c) && session.labels.contains { $0.hasPrefix(session.typed + String(c)) }
    }

    /// ⌘ with these always goes to the app while hints show: close, quit, hide, minimise, new tab,
    /// new window, reload, and the edit shortcuts. A label using one of them is ⌘-clicked by holding
    /// ⌘ on one of its other letters.
    public static let appShortcutLetters: Set<Character> = ["w", "q", "h", "m", "t", "n", "r", "c", "v", "x", "z", "a"]

    /// Checked before anything else. Matches held-down repeats too, so they don't leak into the app;
    /// the caller acts only on the first press.
    public static func globalCommand(_ k: KeyInput) -> GlobalCommand? {
        guard k.keyCode == vKeyCode, k.command, k.option, k.control else { return nil }
        return k.shift ? .cycleAppRule : .toggleEnabled
    }

    /// `focusIsEditable` costs an Accessibility round trip, so it is only called for VimE's plain keys.
    /// `escLeavesTextField`: Esc in a text field means "leave it" (only offered where plain keys work).
    public mutating func route(_ k: KeyInput, mode: Mode, plainKeysAllowed: Bool, escLeavesTextField: Bool = false,
                               now: TimeInterval = 0, focusIsEditable: () -> Bool) -> KeyAction {
        switch mode {
        case .insert:
            pendingG = false
            let plainEsc = k.keyCode == Self.escapeKeyCode && !k.option && !k.command && !k.control && !k.shift
            return plainEsc && !k.isRepeat ? .exitInsert : .pass
        case .passthrough:
            if k.keyCode == Self.escapeKeyCode && !k.option && !k.command && !k.control && !k.shift {
                pendingG = false
                guard plainKeysAllowed, escLeavesTextField, !k.isRepeat, focusIsEditable() else { return .pass }
                return .leaveTextField
            }
            return routePassthrough(k, plainKeysAllowed: plainKeysAllowed, now: now, focusIsEditable: focusIsEditable)
        case .hint:
            pendingG = false
            if k.keyCode == Self.escapeKeyCode { return .exitHint }
            // ⌥F again closes hints, like pressing a toggle twice.
            if k.option && !k.command && !k.control && k.keyCode == Self.fKeyCode { return k.isRepeat ? .swallow : .exitHint }
            if k.isRepeat { return .swallow }
            if k.keyCode == Self.deleteKeyCode { return .backspace }
            if k.control { return .exitHint }
            if k.characters.count == 1, let c = k.characters.lowercased().first, c.isLetter {
                return .type(c, k.command ? .command : k.shift ? .secondary : .primary)
            }
            // ⌘ with anything else (⌘Tab, ⌘Space…) means the user moved on: let it through.
            return k.command ? .exitHintAndPass : .swallow
        }
    }

    private mutating func routePassthrough(_ k: KeyInput, plainKeysAllowed: Bool, now: TimeInterval,
                                           focusIsEditable: () -> Bool) -> KeyAction {
        let wasPendingG = pendingG && now - pendingGAt <= Self.gTimeout
        pendingG = false

        // ⌥F works everywhere, including text fields.
        if k.option && !k.command && !k.control && k.keyCode == Self.fKeyCode {
            return k.isRepeat ? .pass : .enterHint
        }
        guard plainKeysAllowed, !k.option, !k.command, !k.control,
              Self.plainKeys.contains(k.characters), !focusIsEditable()
        else { return .pass }

        switch k.characters {
        case "f": return k.isRepeat ? .pass : .enterHint
        case "j": return .scroll(.down, isRepeat: k.isRepeat)
        case "k": return .scroll(.up, isRepeat: k.isRepeat)
        case "h": return .scroll(.left, isRepeat: k.isRepeat)
        case "l": return .scroll(.right, isRepeat: k.isRepeat)
        case "d": return .scroll(.halfPageDown, isRepeat: k.isRepeat)
        case "u": return .scroll(.halfPageUp, isRepeat: k.isRepeat)
        case "G": return .scroll(.bottom, isRepeat: false)
        case "?": return k.isRepeat ? .swallow : .showHelp
        case "i": return k.isRepeat ? .swallow : .enterInsert
        case "g":
            if wasPendingG { return .scroll(.top, isRepeat: false) }
            pendingG = true
            pendingGAt = now
            return .swallow
        default: return .pass
        }
    }
}
