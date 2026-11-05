import Foundation
import Testing
@testable import AsideCore

@MainActor
struct AssistantSessionTests {
    let fake = FakeClaude()
    let speaker = FakeSpeaker()

    var dataDirectory: URL { fake.directory.appending(path: "data") }

    func session(claude: String?) -> AssistantSession {
        AssistantSession(dataDirectory: dataDirectory, claudePath: claude ?? "/missing/claude", speaker: speaker, compactAt: 80_000)
    }

    var saved: String? {
        (try? String(contentsOf: dataDirectory.appending(path: "session-id"), encoding: .utf8))?.trimmingCharacters(in: .newlines)
    }

    /// What the fake claude holds for `session`: each question's input line, or "summary" once compacted.
    func transcript(_ session: String?) -> String {
        (try? String(contentsOf: dataDirectory.appending(path: "workspace/.sessions/\(session ?? "")"), encoding: .utf8)) ?? ""
    }

    /// Waits up to 5 s for `condition`.
    func eventually(_ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition() {
            guard ContinuousClock.now < deadline else { Issue.record("Still waiting after 5 s"); return }
            try? await Task.sleep(for: .milliseconds(10))
        }
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

    @Test func newConversationStartsAFreshProcessAndForgetsTheSession() async throws {
        let session = session(claude: try fake.write())
        session.send("hello")
        await settle(session)
        let first = try #require(saved)
        #expect(session.sessionID == first)
        session.startNewConversation()
        #expect(session.conversation.isEmpty)
        #expect(session.sessionID == nil)
        #expect(saved == nil)
        session.send("fresh")
        await settle(session)
        #expect(answers(session) == ["Answer 1: fresh"])
        #expect(saved != nil && saved != first)
    }

    @Test func theConversationOutlastsARelaunch() async throws {
        let claude = try fake.write()
        let before = session(claude: claude)
        before.send("hello")
        await settle(before)

        let after = session(claude: claude)
        #expect(after.sessionID == saved)
        #expect(after.conversation.isEmpty)
        after.send("again")
        await settle(after)
        #expect(answers(after) == ["Answer 2: again"])
    }

    @Test func claudeStoppingShowsAndTheNextQuestionContinues() async throws {
        let session = session(claude: try fake.write())
        session.send("hello")
        await settle(session)
        session.send("boom")
        await settle(session)
        #expect(session.conversation.exchanges[1].error
            == "claude stopped (exit status 3): something broke. Your next question continues the conversation.")
        session.send("after")
        await settle(session)
        #expect(session.conversation.exchanges[2].answer == "Answer 3: after")
    }

    @Test func aSessionThatCantBeResumedIsForgotten() async throws {
        try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        try "11111111-2222-3333-4444-555555555555\n".write(to: dataDirectory.appending(path: "session-id"), atomically: true, encoding: .utf8)
        let session = session(claude: try fake.write())
        session.prepare()
        await eventually { session.conversation.exchanges.last?.error != nil }
        #expect(session.conversation.exchanges.last?.error == "Couldn't continue the conversation (exit status 1): "
            + "No conversation found with session ID: 11111111-2222-3333-4444-555555555555. Your next question starts a new conversation.")
        #expect(saved == nil)
        session.send("hello")
        await settle(session)
        #expect(answers(session).last == "Answer 1: hello")
    }

    @Test func missingClaudeShowsWhenAsking() async {
        let session = session(claude: nil)
        session.prepare()
        session.send("hello")
        await settle(session)
        #expect(session.claude == .missing)
        #expect(session.conversation.exchanges.map(\.error) == [AssistantSession.missingMessage])
    }

    @Test func aBigConversationIsCompactedAndTheCopyTakesOver() async throws {
        let session = session(claude: try fake.write())
        session.send("small")
        await settle(session)
        let original = try #require(saved)
        session.send("big")
        await settle(session)
        #expect(saved == original, "Still answering from the original while the copy compacts")

        await eventually { saved != original }
        let compacted = try #require(saved)
        #expect(transcript(compacted) == "summary: small big \n")
        session.send("next")
        await settle(session)
        #expect(answers(session).last == "Answer 2: next", "The summary and this question")
        #expect(transcript(compacted).contains("next"), "The copy answered")
        #expect(!transcript(original).contains("next"))
    }

    @Test func theCompactedCopyStartsWithMemorySavedBeforeTheFork() async throws {
        let session = session(claude: try fake.write())
        session.send("remember tea")
        await settle(session)
        let original = try #require(saved)
        session.send("big")
        await settle(session)
        await eventually { saved != original }
        session.send("recall")
        await settle(session)
        // The original claude started before the fact was saved, so only the copy knows it.
        #expect(answers(session).last == "Answer 2: Knows a fact.")
    }

    @Test func aQuestionDuringCompactionDropsTheCopyAndItRetries() async throws {
        let session = session(claude: try fake.write())
        session.send("big")
        await settle(session)
        let original = try #require(saved)
        session.send("quick")
        await settle(session)
        #expect(answers(session) == ["Answer 1: big", "Answer 2: quick"])
        #expect(saved == original)

        // That turn ended past the limit too, so a new copy compacts and takes over. The first copy,
        // forked before "quick", would have summarized only "big".
        await eventually { saved != original }
        #expect(transcript(saved) == "summary: big quick \n")
    }

    @Test func newDropsAQuestionStillWaitingForClaude() async throws {
        let session = session(claude: try fake.write())
        session.send("old")
        session.startNewConversation()
        session.send("fresh")
        await settle(session)
        #expect(answers(session) == ["Answer 1: fresh"])
        try await Task.sleep(for: .milliseconds(200))
        #expect(answers(session) == ["Answer 1: fresh"])
        #expect(!transcript(saved).contains("old"))
    }

    @Test func newConversationDropsACompaction() async throws {
        let session = session(claude: try fake.write())
        session.send("big")
        await settle(session)
        session.startNewConversation()
        try await Task.sleep(for: .milliseconds(600))
        #expect(saved == nil, "The copy finished after New and must not take over")
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
