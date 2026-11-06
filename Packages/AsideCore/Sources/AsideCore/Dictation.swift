import Foundation
import Observation

/// Speaking anywhere and having the words pasted at the cursor, without Claude. The dictation hotkey starts
/// listening; the next press, or Return, pastes what was heard; Esc throws it away. Decision 28.
@MainActor @Observable
public final class Dictation {
    public enum State: Equatable, Sendable {
        case off
        /// Getting ready to listen, and why it takes a moment.
        case starting(String)
        case listening
        /// The paste press came; waiting for the last words.
        case finishing
        /// Shown for a while after dictating, then off.
        case message(Message)
    }

    public enum Message: Equatable, Sendable {
        case heardNothing
        /// Aside can't press Command-V without Accessibility, so the words were left on the clipboard.
        case needsAccessibility
        case failed(String)

        public var text: String {
            switch self {
            case .heardNothing: "Didn't hear anything"
            case .needsAccessibility: "Aside needs Accessibility to paste"
            case .failed(let reason): reason
            }
        }
    }

    public enum PasteResult: Sendable {
        case pasted
        /// Not pasted; the words are on the clipboard.
        case needsAccessibility
    }

    public private(set) var state = State.off
    /// While listening, how loud the microphone is, from 0 to 1.
    public private(set) var level: Float = 0

    /// From the first press until the words are pasted or thrown away. Return and Esc belong to dictation meanwhile.
    public var isDictating: Bool {
        switch state {
        case .starting, .listening, .finishing: true
        case .off, .message: false
        }
    }

    @ObservationIgnored private let listen: @MainActor () -> any Listener
    @ObservationIgnored private let paste: @MainActor (String) throws -> PasteResult
    @ObservationIgnored private let shownFor: @Sendable (Message) -> Duration
    @ObservationIgnored private var listener: (any Listener)?
    /// Counts messages, so a message's timer doesn't hide a later one.
    @ObservationIgnored private var shown = 0

    /// - Parameters:
    ///   - listen: Starts a new stretch of listening.
    ///   - paste: Pastes the words at the cursor of the app in front.
    ///   - shownFor: How long each message stays.
    public init(
        listen: @escaping @MainActor () -> any Listener,
        paste: @escaping @MainActor (String) throws -> PasteResult,
        shownFor: @escaping @Sendable (Message) -> Duration = Dictation.shownFor
    ) {
        self.listen = listen
        self.paste = paste
        self.shownFor = shownFor
    }

    /// "Didn't hear anything" is gone in a moment; a problem stays long enough to read and act on.
    public nonisolated static func shownFor(_ message: Message) -> Duration {
        message == .heardNothing ? .seconds(2) : .seconds(8)
    }

    /// The dictation hotkey: starts listening, or pastes what was heard. Pressed before the microphone is on,
    /// it stops, since nothing can have been heard.
    public func toggle() {
        switch state {
        case .off, .message: start()
        case .starting: cancel()
        case .listening: finish()
        case .finishing: break
        }
    }

    /// Return: pastes what was heard once the last words are in.
    public func finish() {
        switch state {
        case .listening:
            state = .finishing
            listener?.finish()
        case .starting: cancel()
        case .off, .finishing, .message: break
        }
    }

    /// Esc, the panel opening, or a message dismissed: stops listening, drops what was heard and hides the pill.
    public func cancel() {
        if let listener {
            listener.cancel()
            self.listener = nil
            Log.voice.info("Dictation cancelled")
        }
        state = .off
        level = 0
    }

    private func start() {
        let listener = listen()
        self.listener = listener
        state = .starting("Starting the microphone…")
        level = 0
        Log.voice.info("Dictation starting")
        Task { await follow(listener) }
    }

    private func follow(_ listener: any Listener) async {
        var heard = ""
        do {
            for try await event in listener.events {
                // A listener that was cancelled no longer speaks for dictation.
                guard listener === self.listener else { return }
                switch event {
                case .preparing(let reason): state = .starting(reason)
                case .listening:
                    state = .listening
                    Log.voice.info("Dictation listening")
                case .heard(let words): heard = words
                case .level(let level): self.level = level
                }
            }
        } catch {
            guard listener === self.listener else { return }
            Log.voice.error("Dictation failed: \(error.localizedDescription, privacy: .public)")
            return done(.failed(error.localizedDescription))
        }
        guard listener === self.listener else { return }
        let words = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else {
            Log.voice.info("Dictation heard nothing")
            return done(.heardNothing)
        }
        do {
            switch try paste(words) {
            case .pasted:
                Log.voice.info("Dictation pasted \(words.count) characters")
                done(nil)
            case .needsAccessibility:
                Log.voice.error("Dictation not pasted: no Accessibility permission")
                done(.needsAccessibility)
            }
        } catch {
            Log.voice.error("Dictation paste failed: \(error.localizedDescription, privacy: .public)")
            done(.failed("Couldn't paste: \(error.localizedDescription)"))
        }
    }

    /// Listening is over: hides the pill, or shows `message` in it for a while.
    private func done(_ message: Message?) {
        listener = nil
        level = 0
        guard let message else { state = .off; return }
        state = .message(message)
        shown += 1
        let shown = shown
        Task {
            try? await Task.sleep(for: shownFor(message))
            if self.shown == shown, state == .message(message) { state = .off }
        }
    }
}
