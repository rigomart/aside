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

    func waitForApproval(_ session: AssistantSession) async {
        let deadline = ContinuousClock.now + .seconds(5)
        while session.conversation.exchanges.last?.approval == nil {
            guard ContinuousClock.now < deadline else { Issue.record("No approval asked after 5 s"); return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func allowingAToolLetsClaudeUseIt() async throws {
        let session = session(claude: try fake.write())
        session.send("approve")
        await waitForApproval(session)
        #expect(session.conversation.exchanges[0].approval?.detail == "note.md")
        #expect(session.conversation.isResponding)
        session.answerApproval(allow: true)
        #expect(session.conversation.exchanges[0].approval == nil)
        await settle(session)
        #expect(answers(session) == ["Answer 1: Allowed: wrote note.md."])
    }

    @Test func denyingAToolTellsClaude() async throws {
        let session = session(claude: try fake.write())
        session.send("approve")
        await waitForApproval(session)
        session.answerApproval(allow: false)
        await settle(session)
        #expect(answers(session) == ["Answer 1: Denied: The owner declined."])
    }

    @Test func writesTheWorkspaceInstructions() async throws {
        let session = session(claude: try fake.write())
        session.send("hello")
        await settle(session)
        let instructions = try String(contentsOf: fake.directory.appending(path: "data/workspace/CLAUDE.md"), encoding: .utf8)
        let memory = fake.directory.appending(path: "data/memory/MEMORY.md")
        #expect(instructions == Workspace.instructions(memory: memory))
        #expect(instructions.contains("- Search the web for anything current: news, prices, schedules, versions, opening hours.\n"))
        #expect(instructions.contains("- Your memory file is \(memory.path): one fact per line"))
        #expect(instructions.contains("- You can't see their screen or files. Your only tools are web search, reading web pages, "
            + "and your memory file. Use the file tools only on your memory file.\n"))
    }

    @Test func savesAndRemovalsShowAndAreNotRead() async throws {
        let session = session(claude: try fake.write())
        session.send("remember tea", aloud: true)
        await settle(session)
        session.send("remember cats")
        await settle(session)
        session.send("forget both")
        await settle(session)
        #expect(session.conversation.exchanges.map(\.memoryNotes)
            == [["Remembered: remember tea"], ["Remembered: remember cats"], ["Forgot: remember tea", "Forgot: remember cats"]])
        #expect(speaker.sentences == ["Answer 1: remember tea"])
        let file = try String(contentsOf: fake.directory.appending(path: "data/memory/MEMORY.md"), encoding: .utf8)
        #expect(file == Memory.header)
    }

    @Test func aMemoryThatCantBeReadShowsAndRecovers() async throws {
        let session = session(claude: try fake.write())
        session.send("hello")
        await settle(session)
        let file = fake.directory.appending(path: "data/memory/MEMORY.md").path
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file)
        session.send("again")
        await settle(session)
        #expect(session.conversation.exchanges[1].memoryNotes.count == 1)
        #expect(session.conversation.exchanges[1].memoryNotes.first?.hasPrefix("Couldn't read memory: ") == true)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file)
        session.send("remember tea")
        await settle(session)
        #expect(session.conversation.exchanges[2].memoryNotes == ["Remembered: remember tea"])
    }

    @Test func aSaveJustBeforeClaudeExitsShows() async throws {
        let session = session(claude: try fake.write("""
            #!/bin/bash
            read -r line
            echo "- You like tea." >> ../memory/MEMORY.md
            exit 3
            """))
        session.send("hello")
        await settle(session)
        #expect(session.conversation.exchanges[0].memoryNotes == ["Remembered: You like tea."])
        #expect(session.conversation.exchanges[0].error?.hasPrefix("claude stopped (exit status 3)") == true)
    }

    @Test func aNewClaudeStartsWithWhatWasSaved() async throws {
        let session = session(claude: try fake.write())
        session.send("recall")
        await settle(session)
        session.send("remember tea")
        await settle(session)
        session.startNewConversation()
        session.send("recall")
        await settle(session)
        #expect(answers(session) == ["Answer 1: Knows a fact."])
        #expect(session.conversation.exchanges[0].memoryNotes.isEmpty)
    }
}
