import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Opens and closes the panel. Default: Control-Option-Space.
    static let togglePanel = Self("togglePanel", initial: .init(.space, modifiers: [.control, .option]))
    /// Opens the panel listening; pressed again, sends what was heard. Default: Control-Option-Shift-Space.
    static let talk = Self("talk", initial: .init(.space, modifiers: [.control, .option, .shift]))
    /// Starts dictating; pressed again, pastes what was heard at the cursor. Default: Control-Option-D.
    static let dictate = Self("dictate", initial: .init(.d, modifiers: [.control, .option]))
}
