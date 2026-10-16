import Foundation
import Testing
@testable import AsideCore

/// A listener the test drives: `hear` stands for words being recognized, `finish` ends with `finalWords`.
final class FakeListener: Listener {
    let events: AsyncThrowingStream<ListenerEvent, any Error>
    private let output: AsyncThrowingStream<ListenerEvent, any Error>.Continuation

    init() {
        (events, output) = AsyncThrowingStream.makeStream(of: ListenerEvent.self)
    }

    func listen() { output.yield(.listening) }
    func hear(_ words: String) { output.yield(.heard(words)) }
    func fail(_ message: String) { output.finish(throwing: ListenError(message)) }
    func finish() { output.finish() }
    func cancel() { output.finish() }
}

@MainActor
struct ComposerTests {
    let fake = FakeClaude()
    let listener = FakeListener()
    let speaker = FakeSpeaker()

    func composer() throws -> (Composer, AssistantSession) {
        let session = AssistantSession(
            dataDirectory: fake.directory.appending(path: "data"), claudePath: try fake.write(), speaker: speaker
        )
        return (Composer(session: session, listen: { [listener] in listener }), session)
    }

    /// Waits for `condition`, which the composer reaches after handling a listener event.
    func eventually(_ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition() {
            guard ContinuousClock.now < deadline else { Issue.record("Condition not met after 5 s"); return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func secondPressSendsWhatWasHeard() async throws {
        let (composer, session) = try composer()
        composer.toggleTalking()
        #expect(composer.voice == .starting("Starting the microphone…"))
        listener.listen()
        listener.hear("What is")
        listener.hear("What is the time?")
        await eventually { composer.text == "What is the time?" }
        #expect(composer.voice == .listening)

        composer.toggleTalking()
        #expect(composer.voice == .finishing)
        await eventually { composer.voice == .off }
        #expect(session.conversation.exchanges.map(\.question) == ["What is the time?"])
        #expect(composer.text == "")
    }

    @Test func returnWhileListeningSendsToo() async throws {
        let (composer, session) = try composer()
        composer.toggleTalking()
        listener.listen()
        listener.hear("Hello")
        await eventually { composer.text == "Hello" }
        composer.submit()
        await eventually { !session.conversation.isEmpty }
        #expect(session.conversation.exchanges.map(\.question) == ["Hello"])
    }

    @Test func speechFollowsTextTypedBefore() async throws {
        let (composer, _) = try composer()
        composer.edit("Translate")
        composer.toggleTalking()
        listener.listen()
        listener.hear("good morning")
        await eventually { composer.text == "Translate good morning" }
    }

    @Test func escPutsTheFieldBack() async throws {
        let (composer, _) = try composer()
        composer.edit("Typed")
        composer.toggleTalking()
        listener.listen()
        listener.hear("spoken")
        await eventually { composer.text == "Typed spoken" }
        composer.cancelTalking()
        #expect(composer.text == "Typed")
        #expect(composer.voice == .off)
    }

    @Test func closingThePanelKeepsWhatWasHeardUnsent() async throws {
        let (composer, session) = try composer()
        composer.toggleTalking()
        listener.listen()
        listener.hear("Half a thought")
        await eventually { composer.text == "Half a thought" }
        composer.stopTalking()
        #expect(composer.text == "Half a thought")
        #expect(composer.voice == .off)
        #expect(session.conversation.isEmpty)
    }

    @Test func typingStopsListeningAndKeepsTheEdit() async throws {
        let (composer, session) = try composer()
        composer.toggleTalking()
        listener.listen()
        listener.hear("Wether")
        await eventually { composer.text == "Wether" }
        composer.edit("Weather")
        listener.hear("ignored")
        #expect(composer.voice == .off)
        #expect(composer.text == "Weather")
        composer.submit()
        #expect(session.conversation.exchanges.map(\.question) == ["Weather"])
    }

    @Test func theFieldReportingItsOwnTextKeepsListening() async throws {
        let (composer, _) = try composer()
        composer.toggleTalking()
        listener.listen()
        listener.hear("What")
        await eventually { composer.text == "What" }
        composer.edit("What")
        listener.hear("What is it?")
        await eventually { composer.text == "What is it?" }
        #expect(composer.voice == .listening)
    }

    @Test func hearingNothingSaysSo() async throws {
        let (composer, session) = try composer()
        composer.toggleTalking()
        listener.listen()
        await eventually { composer.voice == .listening }
        composer.toggleTalking()
        await eventually { composer.voice == .off }
        #expect(composer.voiceMessage == Composer.heardNothing)
        #expect(session.conversation.isEmpty)
    }

    @Test func failureShowsAndKeepsTheText() async throws {
        let (composer, session) = try composer()
        composer.toggleTalking()
        listener.listen()
        listener.hear("Some words")
        listener.fail("Couldn't listen: broken")
        await eventually { composer.voice == .off }
        #expect(composer.voiceMessage == "Couldn't listen: broken")
        #expect(composer.text == "Some words")
        #expect(session.conversation.isEmpty)
    }

    @Test func theAnswerToASpokenQuestionIsReadAloud() async throws {
        let (composer, session) = try composer()
        composer.toggleTalking()
        listener.listen()
        listener.hear("What is the time?")
        await eventually { composer.text == "What is the time?" }
        composer.toggleTalking()
        await eventually { session.conversation.exchanges.first?.isFinished == true }
        #expect(speaker.sentences == ["Answer 1: What is the time?"])
        #expect(session.isReadingAloud)
    }

    @Test func theAnswerToATypedQuestionIsNot() async throws {
        let (composer, session) = try composer()
        composer.edit("What is the time?")
        composer.submit()
        await eventually { session.conversation.exchanges.first?.isFinished == true }
        #expect(speaker.sentences.isEmpty)
        #expect(!session.isReadingAloud)
    }

    @Test func talkingStopsReading() async throws {
        let (composer, session) = try composer()
        composer.toggleTalking()
        listener.listen()
        listener.hear("Hello")
        await eventually { composer.text == "Hello" }
        composer.toggleTalking()
        await eventually { session.conversation.exchanges.first?.isFinished == true }
        #expect(session.isReadingAloud)

        composer.toggleTalking()
        #expect(!session.isReadingAloud)
        #expect(composer.voice == .starting("Starting the microphone…"))
    }

    @Test func pressingWhileStartingStops() async throws {
        let (composer, _) = try composer()
        composer.toggleTalking()
        composer.toggleTalking()
        #expect(composer.voice == .off)
    }
}
