import Observation

/// Reads one answer aloud while it streams in, a sentence at a time, leaving out Markdown and code.
@MainActor @Observable
final class Narrator {
    /// From `start` until the answer has ended and its last sentence has been said, or `stop()`.
    private(set) var isReading = false

    @ObservationIgnored private let speaker: any Speaker
    /// The exchange whose answer is being read.
    @ObservationIgnored private var reading: Conversation.Exchange.ID?
    /// How many characters of the answer's spoken text have been handed to the speaker.
    @ObservationIgnored private var handedOver = 0
    /// Sentences handed to the speaker and not yet said.
    @ObservationIgnored private var unsaid = 0
    @ObservationIgnored private var answerEnded = false

    init(speaker: any Speaker) {
        self.speaker = speaker
    }

    /// Reads the answer to exchange `id` as `follow` brings it in. Stops anything being read.
    func start(_ id: Conversation.Exchange.ID) {
        stop()
        reading = id
        isReading = true
    }

    /// Says the sentences of `exchange`'s answer that are complete and not yet said. The last one waits
    /// for more text, unless the answer ended or paused for a tool.
    func follow(_ exchange: Conversation.Exchange) {
        guard exchange.id == reading, !answerEnded else { return }
        let text = SpokenText.prose(exchange.answer)
        let complete = exchange.isFinished || exchange.activity != nil
        let (sentences, end) = SpokenText.sentences(in: text, after: handedOver, includingLast: complete)
        handedOver = end
        for sentence in sentences {
            unsaid += 1
            speaker.say(sentence) { [weak self] in
                self?.unsaid -= 1
                self?.endIfDone()
            }
        }
        if exchange.isFinished {
            answerEnded = true
            endIfDone()
        }
    }

    /// Stops reading, mid-word, and drops the rest of the answer.
    func stop() {
        guard reading != nil else { return }
        speaker.stop()
        Log.voice.info("Stopped reading aloud")
        reset()
    }

    private func endIfDone() {
        guard answerEnded, unsaid == 0 else { return }
        Log.voice.info("Finished reading aloud")
        reset()
    }

    private func reset() {
        reading = nil
        handedOver = 0
        unsaid = 0
        answerEnded = false
        isReading = false
    }
}
