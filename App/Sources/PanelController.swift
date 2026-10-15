import AppKit
import AsideCore
import SwiftUI

/// Owns the floating panel: where it appears, and how it opens and closes.
final class PanelController {
    private let panel: FloatingPanel

    init(model: PanelModel) {
        panel = FloatingPanel(content: PanelView(model: model))
    }

    func toggle() {
        panel.isVisible ? hide() : show()
    }

    /// Shows the panel near the top of the screen the pointer is on, without activating the app,
    /// so the app the user was in stays frontmost.
    func show() {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.minY + frame.height * 0.75 - size.height))
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
    init(content: some View) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        animationBehavior = .utilityWindow

        let hosting = NSHostingView(rootView: content)
        contentView = hosting
        setContentSize(hosting.fittingSize)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
        Log.panel.info("Hidden: Esc")
    }

    override func resignKey() {
        super.resignKey()
        orderOut(nil)
        Log.panel.info("Hidden: lost focus")
    }
}
