import AppKit
import AsideCore
import SwiftUI

/// Owns the floating panel: where it appears, and how it opens and closes.
final class PanelController {
    private let panel: FloatingPanel
    private let session: AssistantSession
    private let composer: Composer

    init(session: AssistantSession, composer: Composer) {
        self.session = session
        self.composer = composer
        panel = FloatingPanel(content: PanelView(session: session, composer: composer))
        // Esc throws away what was heard and stops reading aloud; any other way of closing keeps
        // what was heard in the field and keeps reading.
        panel.onEscape = {
            composer.cancelTalking()
            session.stopReadingAloud()
        }
        panel.onClose = { composer.stopTalking() }
    }

    func toggle() {
        panel.isVisible ? hide() : show()
    }

    /// The talk hotkey: opens the panel listening, or sends what was heard.
    func talk() {
        if !panel.isVisible { show() }
        composer.toggleTalking()
    }

    /// Shows the panel in the bottom-right corner of the screen the pointer is on, above the Dock, without
    /// activating the app, so the app the user was in stays frontmost. The field is at the bottom and the
    /// answer grows up from it. Starts claude, so it's ready for the question.
    func show() {
        session.prepare()
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.maxX - panel.frame.width, y: frame.minY))
        }
        panel.makeKeyAndOrderFront(nil)
        Log.panel.info("Shown")
    }

    func hide() {
        panel.orderOut(nil)
        Log.panel.info("Hidden")
    }
}

/// A borderless, non-activating panel that floats over other apps, including full-screen ones,
/// and on every Space. Esc or a click outside closes it.
private final class FloatingPanel: NSPanel {
    var onEscape: () -> Void = {}
    /// Called on every close: each one resigns key first.
    var onClose: () -> Void = {}

    init(content: some View) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        // The glass draws its own shadows; the window's would trace the transparent space between them.
        hasShadow = false
        isMovableByWindowBackground = true
        animationBehavior = .utilityWindow
        identifier = NSUserInterfaceItemIdentifier("panel")

        let hosting = NSHostingView(rootView: content)
        contentView = hosting
        setContentSize(hosting.fittingSize)
    }

    /// SwiftUI resizes the window as its content changes, keeping its top edge. Keep the bottom edge
    /// instead, so the field stays in the corner and the answer grows upward.
    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        var frame = frameRect
        if frame.size != self.frame.size { frame.origin.y = self.frame.minY }
        super.setFrame(frame, display: flag)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onEscape()
        orderOut(nil)
        Log.panel.info("Hidden: Esc")
    }

    override func resignKey() {
        super.resignKey()
        onClose()
        orderOut(nil)
        Log.panel.info("Hidden: lost focus")
    }
}
