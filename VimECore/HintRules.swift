import CoreGraphics

/// Which Accessibility elements get a hint while walking a window's tree.
/// Pure, so the walk's choices are unit tested; the walk itself lives in the app.
public enum HintRules {
    /// Always clickable.
    static let controlRoles: Set<String> = [
        "AXButton", "AXLink", "AXCheckBox", "AXRadioButton", "AXMenuItem", "AXMenuBarItem",
        "AXPopUpButton", "AXMenuButton", "AXTextField", "AXTextArea", "AXComboBox", "AXSearchField",
        "AXTab", "AXDisclosureTriangle", "AXSlider", "AXIncrementor",
    ]
    /// Parts of a list or table row that the row's own hint already covers.
    static let rowPartRoles: Set<String> = ["AXCell", "AXTextField", "AXStaticText", "AXImage", "AXDisclosureTriangle"]
    /// Show only the part of their contents that lies inside them.
    static let clippingRoles: Set<String> = ["AXScrollArea", "AXWebArea"]
    /// Drawn over their parent rather than inside it, so they escape its clip.
    static let floatingRoles: Set<String> = ["AXMenu", "AXPopover", "AXSheet"]
    /// Generic containers. Chromium marks some pressable (a page-wide click handler); a huge one is noise.
    static let containerRoles: Set<String> = [
        "AXGroup", "AXWebArea", "AXScrollArea", "AXSplitGroup", "AXLayoutArea", "AXUnknown",
        "AXList", "AXOutline", "AXTable",
    ]
    /// Controls whose insides are never separate targets (a link's text, a button's icon).
    static let leafRoles: Set<String> = [
        "AXButton", "AXLink", "AXCheckBox", "AXTextField", "AXSearchField", "AXTextArea",
        "AXSlider", "AXIncrementor", "AXDisclosureTriangle",
    ]
    /// Never targets, so the walk skips asking for their actions.
    static let inertRoles: Set<String> = [
        "AXStaticText", "AXValueIndicator", "AXSplitter", "AXWindow", "AXMenuBar",
    ]
    /// Neither targets nor holding any: their parts (a scroll bar's page buttons) aren't worth a hint.
    static let opaqueRoles: Set<String> = ["AXScrollBar"]
    /// A container covering more than this share of the window is never a target.
    static let maxContainerShare: CGFloat = 0.3
    static let minSide: CGFloat = 8

    public struct Context: Equatable {
        /// Only the part of an element inside this rect is visible. Accessibility space.
        public var clip: CGRect
        /// Area of the window being walked, to spot page-sized containers.
        public var rootArea: CGFloat
        public var inWeb = false
        public var inWebTable = false
        public var inRow = false

        public init(clip: CGRect, rootArea: CGFloat) {
            self.clip = clip
            self.rootArea = rootArea
        }
    }

    public enum Decision: Equatable {
        case target
        case notTarget
        /// A target only if it supports AXPress (costs the caller one more Accessibility call).
        case ifPressable
    }

    /// Whether to skip an element and everything inside it before looking at its frame.
    /// A closed menu has no frame of its own while its items still report stale positions.
    public static func isHidden(role: String?, hasFrame: Bool) -> Bool {
        guard let role else { return false }
        return opaqueRoles.contains(role) || (!hasFrame && floatingRoles.contains(role))
    }

    /// The part of `frame` that is on screen, or nil when the element (and its subtree) is hidden.
    public static func visibleRect(role: String?, frame: CGRect, context: Context) -> CGRect? {
        let clip = role.map(floatingRoles.contains) == true ? CGRect.infinite : context.clip
        let visible = frame.intersection(clip)
        return visible.isNull || visible.isEmpty ? nil : visible
    }

    /// `enabled` is false for greyed-out controls and menu items (and menu separators).
    public static func decide(role: String?, visible: CGRect, enabled: Bool = true, context: Context) -> Decision {
        guard enabled, visible.width >= minSide, visible.height >= minSide else { return .notTarget }
        guard let role else { return .ifPressable }
        if context.inRow && rowPartRoles.contains(role) { return .notTarget }
        if inertRoles.contains(role) { return .notTarget }
        if role == "AXRow" || role == "AXCell" {
            // Native rows select on click; rows of a web data table are just layout.
            return context.inWebTable ? .ifPressable : .target
        }
        if controlRoles.contains(role) { return .target }
        if containerRoles.contains(role), visible.width * visible.height > maxContainerShare * context.rootArea {
            return .notTarget
        }
        return .ifPressable
    }

    /// Whether a target's children are skipped. Tall "buttons" are really cards with controls inside.
    public static func isLeaf(role: String?, visible: CGRect) -> Bool {
        guard let role else { return false }
        return leafRoles.contains(role) && visible.height <= 100
    }

    /// The context an element's children are walked with.
    public static func childContext(role: String?, visible: CGRect?, context: Context) -> Context {
        var next = context
        guard let role else { return next }
        if let visible, clippingRoles.contains(role) || floatingRoles.contains(role) { next.clip = visible }
        switch role {
        case "AXWebArea": next.inWeb = true
        case "AXTable" where context.inWeb: next.inWebTable = true
        case "AXRow": next.inRow = true
        default: break
        }
        return next
    }
}
