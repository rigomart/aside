import AppKit
import AsideCore
import Carbon.HIToolbox

/// Pastes text at the cursor of the app in front: puts it on the clipboard, presses Command-V, then puts back
/// what the clipboard held. Pressing keys in other apps needs Accessibility.
final class Paster {
    /// Long enough for the app in front to read the clipboard after Command-V.
    private static let restoreAfter = Duration.milliseconds(500)
    /// Asks clipboard managers not to record the dictated text (nspasteboard.org).
    private static let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    /// What the clipboard held before the last paste, until it's put back.
    private var saved: [NSPasteboardItem]?
    private var restore: Task<Void, Never>?
    private var askedForAccessibility = false

    func paste(_ text: String) throws -> Dictation.PasteResult {
        let pasteboard = NSPasteboard.general
        // Not `CGPreflightPostEventAccess`: it keeps its first answer until quit, so it misses a change in System Settings.
        guard AXIsProcessTrusted() else {
            if !askedForAccessibility {
                askedForAccessibility = true
                // The value of `kAXTrustedCheckOptionPrompt`, which Swift 6 won't read: it's a global `var`.
                AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            }
            restore?.cancel()
            saved = nil
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            return .needsAccessibility
        }
        // A paste right after another: the clipboard still holds the last dictation, not the owner's.
        restore?.cancel()
        let original = saved ?? Self.copy(of: pasteboard)
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setData(Data(), forType: Self.transient)
        pasteboard.writeObjects([item])
        let ours = pasteboard.changeCount
        // Scheduled before the key press, so the clipboard comes back even if the press fails.
        saved = original
        restore = Task {
            try? await Task.sleep(for: Self.restoreAfter)
            guard !Task.isCancelled else { return }
            saved = nil
            // Something copied meanwhile is the owner's now; leave it.
            guard pasteboard.changeCount == ours else { return }
            pasteboard.clearContents()
            pasteboard.writeObjects(original)
        }
        try Self.pressCommandV()
        return .pasted
    }

    /// Copies the items, since items read from a pasteboard are only valid until its contents change.
    private static func copy(of pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
    }

    private static func pressCommandV() throws {
        let source = CGEventSource(stateID: .combinedSessionState)
        for keyDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: keyDown) else {
                throw PasteError()
            }
            // Only Command, whatever modifiers are still held from the hotkey.
            event.flags = .maskCommand
            event.post(tap: .cghidEventTap)
        }
    }

    private struct PasteError: LocalizedError {
        var errorDescription: String? { "macOS wouldn't make a Command-V key press." }
    }
}
