import Foundation
import Observation

/// What's in the panel's field, typed or spoken, and sending it. The talk hotkey starts listening and
/// the next press sends what was heard; typing stops listening and keeps the text; Esc throws it away.
/// The answer to a question sent while listening is read aloud.
@MainActor @Observable
public final class Composer {
    public enum Voice: Equatable, Sendable {
        case off
        /// Getting ready to listen, and why it takes a moment.
        case starting(String)
        case listening
        /// The send press came; waiting for the last words.
        case finishing
    }

    public static let heardNothing = "Didn't hear anything."

    /// The field's text. While listening, it is what was typed before plus what has been heard.
    public private(set) var text = ""
    public private(set) var voice = Voice.off
    /// Why listening stopped or failed, until the next edit or talk.
    public private(set) var voiceMessage: String?

    @ObservationIgnored private let session: AssistantSession
    @ObservationIgnored private let listen: @MainActor () -> any Listener
    @ObservationIgnored private var listener: (any Listener)?
    @ObservationIgnored private var textBeforeTalking = ""
    @ObservationIgnored private var sendWhenDone = false

    /// - Parameter listen: Starts a new stretch of listening.
    public init(session: AssistantSession, listen: @escaping @MainActor () -> any Listener) {
        self.session = session
        self.listen = listen
    }

    /// The user changed the field. Stops listening first, keeping the text as edited. The field also
    /// reports its own text back unchanged, such as when it gains focus or shows new words; that isn't an edit.
    public func edit(_ newText: String) {
        guard newText != text else { return }
        if listener != nil { stopTalking() }
        text = newText
        voiceMessage = nil
    }

    /// Return. Sends the field's text; while listening, sends once the last words are in.
    public func submit() {
        if voice == .listening { finishTalking() } else if listener == nil { send(aloud: false) }
    }

    /// The talk hotkey: starts listening, or sends what was heard.
    public func toggleTalking() {
        switch voice {
        case .off: startTalking()
        case .starting: stopTalking()
        case .listening: finishTalking()
        case .finishing: break
        }
    }

    /// Esc. Stops listening and puts the field back as it was before talking.
    public func cancelTalking() {
        guard listener != nil else { return }
        stopTalking()
        text = textBeforeTalking
    }

    /// The panel closed. Stops listening and keeps what was heard in the field, unsent.
    public func stopTalking() {
        guard let listener else { return }
        listener.cancel()
        self.listener = nil
        voice = .off
        Log.voice.info("Stopped listening")
    }

    /// Stops reading the last answer aloud first, so the microphone doesn't hear it.
    private func startTalking() {
        session.stopReadingAloud()
        let listener = listen()
        self.listener = listener
        textBeforeTalking = text
        sendWhenDone = false
        voice = .starting("Starting the microphone…")
        voiceMessage = nil
        Log.voice.info("Starting to listen")
        Task { await follow(listener) }
    }

    private func finishTalking() {
        voice = .finishing
        sendWhenDone = true
        listener?.finish()
    }

    private func follow(_ listener: any Listener) async {
        do {
            for try await event in listener.events {
                // A listener that was stopped no longer speaks for the field.
                guard listener === self.listener else { return }
                switch event {
                case .preparing(let reason): voice = .starting(reason)
                case .listening:
                    voice = .listening
                    Log.voice.info("Listening")
                case .heard(let words):
                    text = [textBeforeTalking, words].filter { !$0.isEmpty }.joined(separator: " ")
                }
            }
        } catch {
            guard listener === self.listener else { return }
            Log.voice.error("Listening failed: \(error.localizedDescription, privacy: .public)")
            voiceMessage = error.localizedDescription
        }
        guard listener === self.listener else { return }
        self.listener = nil
        voice = .off
        guard sendWhenDone, voiceMessage == nil else { return }
        if text == textBeforeTalking {
            voiceMessage = Self.heardNothing
        } else {
            send(aloud: true)
        }
    }

    /// Sends the text and clears the field. While an answer is still coming, the text stays.
    private func send(aloud: Bool) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !session.conversation.isResponding else { return }
        session.send(question, aloud: aloud)
        text = ""
    }
}
