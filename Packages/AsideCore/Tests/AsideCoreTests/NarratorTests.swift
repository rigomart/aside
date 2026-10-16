import Testing
@testable import AsideCore

@MainActor
struct NarratorTests {
    let speaker = FakeSpeaker()
    var conversation = Conversation()

    /// Streams `chunks` into the last exchange, following each with the narrator, as the session does.
    mutating func stream(_ chunks: [String], to narrator: Narrator) {
        for chunk in chunks {
            conversation.apply(.text(chunk))
            narrator.follow(conversation.exchanges.last!)
        }
    }

    mutating func end(_ narrator: Narrator) {
        conversation.apply(.turnEnded(error: nil))
        narrator.follow(conversation.exchanges.last!)
    }

    @Test mutating func readsEachSentenceOnceItIsComplete() {
        let narrator = Narrator(speaker: speaker)
        narrator.start(conversation.ask("Weather?"))
        #expect(narrator.isReading)

        stream(["It's **sunny** in", " Lima. It will", " stay warm"], to: narrator)
        #expect(speaker.sentences == ["It's sunny in Lima."])

        end(narrator)
        #expect(speaker.sentences == ["It's sunny in Lima.", "It will stay warm"])
        #expect(narrator.isReading, "Still saying the last sentences")
        speaker.finishSpeaking()
        #expect(!narrator.isReading)
    }

    @Test mutating func aPauseForAToolSaysWhatCameBefore() {
        let narrator = Narrator(speaker: speaker)
        narrator.start(conversation.ask("News?"))
        stream(["Let me check."], to: narrator)
        #expect(speaker.sentences.isEmpty)
        conversation.apply(.toolStarted("WebSearch"))
        narrator.follow(conversation.exchanges.last!)
        #expect(speaker.sentences == ["Let me check."])

        conversation.apply(.textStarted)
        stream(["Prices rose."], to: narrator)
        end(narrator)
        #expect(speaker.sentences == ["Let me check.", "Prices rose."])
    }

    @Test mutating func codeIsSkippedAsItStreams() {
        let narrator = Narrator(speaker: speaker)
        narrator.start(conversation.ask("How?"))
        stream(["Run this:\n``", "`bash\nls -la", "\n```\nThen restart."], to: narrator)
        end(narrator)
        #expect(speaker.sentences == ["Run this:", "Then restart."])
    }

    @Test mutating func stopCutsItOffAndIgnoresTheRest() {
        let narrator = Narrator(speaker: speaker)
        narrator.start(conversation.ask("Story?"))
        stream(["Once upon a time. There was"], to: narrator)
        narrator.stop()
        #expect(!narrator.isReading)
        #expect(speaker.stops == 1)

        stream([" a fox."], to: narrator)
        end(narrator)
        #expect(speaker.sentences == ["Once upon a time."])
    }

    @Test mutating func onlyTheStartedAnswerIsRead() {
        let narrator = Narrator(speaker: speaker)
        conversation.ask("Typed")
        stream(["Not read."], to: narrator)
        end(narrator)
        #expect(speaker.sentences.isEmpty)
        #expect(!narrator.isReading)
    }

    @Test mutating func anEmptyAnswerEndsAtOnce() {
        let narrator = Narrator(speaker: speaker)
        narrator.start(conversation.ask("Fails"))
        conversation.fail("Something broke")
        narrator.follow(conversation.exchanges.last!)
        #expect(speaker.sentences.isEmpty)
        #expect(!narrator.isReading)
    }
}
