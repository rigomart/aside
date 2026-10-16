import Foundation
import Observation

/// The answer being read aloud, split around the sentence being said, for the panel to show as captions.
/// Each part is spoken text: no Markdown or code.
public struct Caption: Equatable, Sendable {
    public var said: String
    public var saying: String
    /// Sentences waiting to be said, then the text not yet handed to the speaker.
    public var coming: String
}

/// Reads one answer aloud while it streams in, a sentence at a time, leaving out Markdown and code.
@MainActor @Observable
final class Narrator {
    /// From `start` until the answer has ended and its last sentence has been said, or `stop()`.
    private(set) var isReading = false
    /// While reading, where the reading is in the answer.
    private(set) var caption: Caption?

    @ObservationIgnored private let speaker: any Speaker
    /// The exchange whose answer is being read.
    @ObservationIgnored private var reading: Conversation.Exchange.ID?
    /// How many characters of the answer's spoken text have been handed to the speaker.
    @ObservationIgnored private var handedOver = 0
    /// Sentences handed to the speaker, in order. The speaker says them one after another, so the first
    /// one not yet said is the one being said.
    @ObservationIgnored private var sentences: [String] = []
    @ObservationIgnored private var saidCount = 0
    /// The answer's spoken text after the sentences handed over.
    @ObservationIgnored private var rest = ""
    @ObservationIgnored private var answerEnded = false

    init(speaker: any Speaker) {
        self.speaker = speaker
    }

    /// Reads the answer to exchange `id` as `follow` brings it in. Stops anything being read.
    func start(_ id: Conversation.Exchange.ID) {
        stop()
        reading = id
        isReading = true
        updateCaption()
    }

    /// Says the sentences of `exchange`'s answer that are complete and not yet said. The last one waits
    /// for more text, unless the answer ended or paused for a tool.
    func follow(_ exchange: Conversation.Exchange) {
        guard exchange.id == reading, !answerEnded else { return }
        let text = SpokenText.prose(exchange.answer)
        let complete = exchange.isFinished || exchange.activity != nil
        let (sentences, end) = SpokenText.sentences(in: text, after: handedOver, includingLast: complete)
        handedOver = end
        rest = String(text.dropFirst(end))
        for sentence in sentences {
            self.sentences.append(sentence)
            speaker.say(sentence) { [weak self] in
                guard let self else { return }
                saidCount += 1
                updateCaption()
                endIfDone()
            }
        }
        updateCaption()
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
        guard answerEnded, saidCount == sentences.count else { return }
        Log.voice.info("Finished reading aloud")
        reset()
    }

    private func reset() {
        reading = nil
        handedOver = 0
        sentences = []
        saidCount = 0
        rest = ""
        answerEnded = false
        isReading = false
        caption = nil
    }

    private func updateCaption() {
        let saying = sentences.indices.contains(saidCount) ? sentences[saidCount] : ""
        let waiting = sentences.dropFirst(saidCount + 1) + [rest.replacing(/\s+/, with: " ")]
        caption = Caption(
            said: sentences.prefix(saidCount).joined(separator: " "),
            saying: saying,
            coming: waiting.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
        )
    }
}
