import AppKit
import AsideCore
import KeyboardShortcuts
import SwiftUI

/// Dictation's pill, and Return and Esc while dictating. The hotkey is wired in `AppDelegate`.
final class DictationController {
    private let dictation: Dictation
    private let pill: PillPanel
    /// Return and Esc as global hotkeys, held only while dictating, since the pill never takes the keyboard.
    private var keys: [Task<Void, Never>] = []

    init(shownFor: @escaping @Sendable (Dictation.Message) -> Duration, listen: @escaping @MainActor () -> any Listener) {
        let paster = Paster()
        let dictation = Dictation(listen: listen, paste: { try paster.paste($0) }, shownFor: shownFor)
        self.dictation = dictation
        pill = PillPanel(content: DictationPill(dictation: dictation))
        Task { [weak self] in
            for await state in Observations({ dictation.state }) { self?.update(state) }
        }
    }

    func toggle() {
        dictation.toggle()
    }

    func cancel() {
        dictation.cancel()
    }

    private func update(_ state: Dictation.State) {
        if dictation.isDictating { holdKeys() } else { releaseKeys() }
        if state == .off {
            pill.orderOut(nil)
        } else if !pill.isVisible {
            pill.show()
        }
    }

    private func holdKeys() {
        guard keys.isEmpty else { return }
        let dictation = dictation
        keys = [
            Task { for await _ in KeyboardShortcuts.events(.keyUp, for: .init(.return)) { dictation.finish() } },
            Task { for await _ in KeyboardShortcuts.events(.keyUp, for: .init(.escape)) { dictation.cancel() } },
        ]
    }

    private func releaseKeys() {
        keys.forEach { $0.cancel() }
        keys = []
    }
}

/// A borderless panel that floats over other apps, including full-screen ones, and never takes the keyboard.
private final class PillPanel: NSPanel {
    init(content: some View) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        animationBehavior = .utilityWindow
        identifier = NSUserInterfaceItemIdentifier("dictationPill")
        let hosting = NSHostingView(rootView: content)
        contentView = hosting
        setContentSize(hosting.fittingSize)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// In the bottom-right corner of the screen the pointer is on, above the Dock, where the panel opens.
    func show() {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            setFrameOrigin(NSPoint(x: frame.maxX - self.frame.width, y: frame.minY))
        }
        orderFrontRegardless()
    }

    /// SwiftUI resizes the window as its content changes. Keep it in the corner.
    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        var frame = frameRect
        if frame.size != self.frame.size {
            frame.origin = NSPoint(x: self.frame.maxX - frame.width, y: self.frame.minY)
        }
        super.setFrame(frame, display: flag)
    }
}

/// While dictating, bars that move with the voice over what the keys do; afterwards, a message if there is one.
private struct DictationPill: View {
    let dictation: Dictation

    private static let accessibilitySettings = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    var body: some View {
        if dictation.state != .off {
            content
                .font(.callout)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .frame(width: 300)
                .glassEffect(.regular, in: .rect(cornerRadius: 22))
                .padding(20)
        }
    }

    @ViewBuilder private var content: some View {
        switch dictation.state {
        case .off: EmptyView()
        case .starting(let reason): listening(status(reason))
        case .listening:
            listening(
                HStack(spacing: 6) {
                    Keycap("return")
                    Text("pastes")
                    Keycap("esc").padding(.leading, 6)
                    Text("cancels")
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Listening · Return pastes · Esc cancels")
                .accessibilityIdentifier("dictationStatus")
            )
        case .finishing: listening(status("Pasting…"))
        case .message(let message): self.message(message)
        }
    }

    private func listening(_ line: some View) -> some View {
        VStack(spacing: 8) {
            VoiceBars(level: dictation.level, count: 23, height: 30)
            line
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func status(_ text: String) -> some View {
        Text(text)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
            .accessibilityIdentifier("dictationStatus")
    }

    private func message(_ message: Dictation.Message) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(message.text, systemImage: message == .heardNothing ? "mic.slash" : "exclamationmark.triangle.fill")
                .foregroundStyle(message == .heardNothing ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("dictationMessage")
            if message == .needsAccessibility {
                Text("What you said is on the clipboard.")
                    .foregroundStyle(.secondary)
                Button("Open Accessibility Settings") {
                    NSWorkspace.shared.open(Self.accessibilitySettings)
                    dictation.cancel()
                }
                .accessibilityIdentifier("openAccessibilitySettings")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
