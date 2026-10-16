import AVFoundation

/// Speaks with the system's speech synthesizer, in the best voice installed for the Mac's language.
/// A Premium or Enhanced voice downloaded in System Settings › Accessibility › Spoken Content wins.
@MainActor
public final class SpeechSpeaker: NSObject, Speaker, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private let voice: AVSpeechSynthesisVoice?
    /// Sentences handed to the synthesizer and not yet said, in the order it says them.
    private var waiting: [(utterance: AVSpeechUtterance, said: @MainActor () -> Void)] = []

    override public init() {
        voice = Self.bestVoice(for: AVSpeechSynthesisVoice.currentLanguageCode())
        super.init()
        synthesizer.delegate = self
        Log.voice.info("Reading aloud with \(self.voice?.identifier ?? "the default voice", privacy: .public)")
    }

    public func say(_ sentence: String, said: @escaping @MainActor () -> Void) {
        let utterance = AVSpeechUtterance(string: sentence)
        utterance.voice = voice
        waiting.append((utterance, said))
        synthesizer.speak(utterance)
    }

    public func stop() {
        waiting.removeAll()
        synthesizer.stopSpeaking(at: .immediate)
    }

    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        // Compared by identity only; `waiting` keeps each utterance alive, so an identity is never reused.
        nonisolated(unsafe) let utterance = utterance
        Task { @MainActor in
            guard let first = waiting.first, first.utterance === utterance else { return }
            waiting.removeFirst()
            first.said()
        }
    }

    /// The highest-quality voice for `language`, leaving out novelty voices and the owner's Personal
    /// Voice (which needs its own permission). Among equals, the language's default voice.
    private static func bestVoice(for language: String) -> AVSpeechSynthesisVoice? {
        let standard = AVSpeechSynthesisVoice(language: language)
        let voices = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language == language && $0.voiceTraits.isDisjoint(with: [.isNoveltyVoice, .isPersonalVoice])
        }
        func rank(_ voice: AVSpeechSynthesisVoice) -> (Int, Int) {
            (voice.quality.rawValue, voice.identifier == standard?.identifier ? 1 : 0)
        }
        return voices.max { rank($0) < rank($1) } ?? standard
    }
}
