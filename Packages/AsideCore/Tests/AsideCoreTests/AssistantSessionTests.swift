import Foundation
import Testing
@testable import AsideCore

@MainActor
struct AssistantSessionTests {
    let fake = FakeClaude()
    let speaker = FakeSpeaker()

    func session(claude: String?, now: @escaping () -> Date = Date.init) -> AssistantSession {
        AssistantSession(
            dataDirectory: fake.directory.appending(path: "data"),
            claudePath: claude ?? "/missing/claude",
            speaker: speaker,
            idleLimit: 600,
            now: now
        )
    }

    func answers(_ session: AssistantSession) -> [String] {
        session.conversation.exchanges.map(\.answer)
    }

    /// Waits for the last question to be answered.
    func settle(_ session: AssistantSession) async {
        let deadline = ContinuousClock.now + .seconds(5)
        while session.conversation.isResponding || session.claude == .searching {
            guard ContinuousClock.now < deadline else { Issue.record("Still responding after 5 s"); return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func followUpsGoToTheSameProcess() async throws {
        let session = session(claude: try fake.write())
        session.send("hello")
        await settle(session)
        session.send("again")
        await settle(session)
        #expect(answers(session) == ["Answer 1: hello", "Answer 2: again"])
        #expect(session.conversation.exchanges.map(\.question) == ["hello", "again"])
    }

    @Test func questionsWhileAnsweringAreIgnored() async throws {
        let session = session(claude: try fake.write())
        session.send("hello")
        session.send("too soon")
        await settle(session)
        #expect(answers(session) == ["Answer 1: hello"])
    }

    @Test func newConversationStartsAFreshProcess() async throws {
        let session = session(claude: try fake.write())
        session.send("hello")
        await settle(session)
        session.startNewConversation()
        #expect(session.conversation.isEmpty)
        session.send("fresh")
        await settle(session)
        #expect(answers(session) == ["Answer 1: fresh"])
    }

    @Test func claudeStoppingShowsAndTheNextQuestionStartsOver() async throws {
        let session = session(claude: try fake.write())
        session.send("boom")
        await settle(session)
        #expect(session.conversation.exchanges[0].error
            == "claude stopped (exit status 3): something broke. Your next question starts a new conversation.")
        session.send("after")
        await settle(session)
        #expect(session.conversation.exchanges[1].answer == "Answer 1: after")
    }

    @Test func missingClaudeShowsWhenAsking() async {
        let session = session(claude: nil)
        session.prepare()
        session.send("hello")
        await settle(session)
        #expect(session.claude == .missing)
        #expect(session.conversation.exchanges.map(\.error) == [AssistantSession.missingMessage])
    }

    @Test func openingAfterTheIdleLimitStartsANewConversation() async throws {
        var time = Date(timeIntervalSince1970: 0)
        let session = session(claude: try fake.write(), now: { time })
        session.send("hello")
        await settle(session)

        time += 599
        session.prepare()
        #expect(answers(session) == ["Answer 1: hello"])

        time += 2
        session.prepare()
        #expect(session.conversation.isEmpty)
        session.send("later")
        await settle(session)
        #expect(answers(session) == ["Answer 1: later"])
    }

    @Test func onlyAnswersAskedAloudAreRead() async throws {
        let session = session(claude: try fake.write())
        session.send("hello", aloud: true)
        #expect(session.isReadingAloud)
        await settle(session)
        #expect(speaker.sentences == ["Answer 1: hello"])
        speaker.finishSpeaking()
        #expect(!session.isReadingAloud)

        session.send("typed")
        await settle(session)
        #expect(speaker.sentences == ["Answer 1: hello"])
        #expect(!session.isReadingAloud)
    }

    @Test func theNextQuestionStopsReading() async throws {
        let session = session(claude: try fake.write())
        session.send("hello", aloud: true)
        await settle(session)
        #expect(session.isReadingAloud, "Still saying the answer")
        session.send("typed")
        #expect(!session.isReadingAloud)
        #expect(speaker.stops == 1)
    }

    @Test func aNewConversationStopsReading() async throws {
        let session = session(claude: try fake.write())
        session.send("hello", aloud: true)
        await settle(session)
        session.startNewConversation()
        #expect(!session.isReadingAloud)
        #expect(speaker.stops == 1)
    }

    @Test func writesTheWorkspaceInstructions() async throws {
        let session = session(claude: try fake.write())
        session.send("hello")
        await settle(session)
        let instructions = try String(contentsOf: fake.directory.appending(path: "data/workspace/CLAUDE.md"), encoding: .utf8)
        #expect(instructions == Workspace.instructions)
    }
}
