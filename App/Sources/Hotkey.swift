import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Opens and closes the panel. Default: Control-Option-Space.
    static let togglePanel = Self("togglePanel", initial: .init(.space, modifiers: [.control, .option]))
}
