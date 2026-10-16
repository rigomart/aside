@testable import AsideCore

/// A speaker the test drives: it keeps what it was asked to say, and `finishSpeaking` stands for the
/// synthesizer saying everything queued.
@MainActor
final class FakeSpeaker: Speaker {
    /// Every sentence it was asked to say, in order, including ones `stop()` dropped.
    private(set) var sentences: [String] = []
    private(set) var stops = 0
    private var waiting: [@MainActor () -> Void] = []

    func say(_ sentence: String, said: @escaping @MainActor () -> Void) {
        sentences.append(sentence)
        waiting.append(said)
    }

    func stop() {
        waiting.removeAll()
        stops += 1
    }

    /// Stands for the synthesizer finishing the sentence it is saying.
    func finishSentence() {
        guard !waiting.isEmpty else { return }
        waiting.removeFirst()()
    }

    func finishSpeaking() {
        let done = waiting
        waiting.removeAll()
        done.forEach { $0() }
    }
}
