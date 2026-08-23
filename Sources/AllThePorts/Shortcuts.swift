import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// The global "open the popover" shortcut, configurable in Settings.
    /// KeyboardShortcuts owns recording, validation and persistence — which
    /// also means Option/Shift combos record correctly (it works from key
    /// codes, not characters).
    static let togglePopover = Self("togglePopover")
}
