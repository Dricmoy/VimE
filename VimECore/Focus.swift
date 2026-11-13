/// Whether the user is typing, from what the focused app reports. Plain keys must never fire then.
public enum Focus {
    /// Containers whose highlighted row a palette or combobox reports as focused (aria-activedescendant)
    /// while the caret stays in its text field.
    static let optionContainerRoles: Set<String> = ["AXList", "AXListBox", "AXOutline", "AXTable", "AXGrid", "AXMenu"]
    /// How far up from the focused element to look for such a container.
    public static let optionSearchDepth = 6

    /// Whether to ask where the caret is. Only when focus sits on an option, because Chromium leaves the
    /// caret parked in the last text field after focus moves to a button or the page.
    public static func shouldCheckCaret(focusAncestorRoles: [String]) -> Bool {
        focusAncestorRoles.prefix(optionSearchDepth).contains(where: optionContainerRoles.contains)
    }
}
