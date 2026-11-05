import Foundation
import Testing
@testable import AsideCore

struct ClaudeProcessTests {
    let fake = FakeClaude()

    @Test func inputLineIsOneStreamJSONUserMessage() {
        let line = String(decoding: ClaudeProcess.inputLine(#"Say "hi" / bye"#), as: UTF8.self)
        #expect(line == #"{"message":{"content":"Say \"hi\" / bye","role":"user"},"type":"user"}"# + "\n")
    }

    let memory = Memory(directory: URL(filePath: "/data/App Support/memory/"), text: "# Memory\n\n- Likes tea.\n")

    @Test func argumentsKeepTheOwnersSetupOut() {
        let arguments = ClaudeProcess.arguments(model: "sonnet", memory: memory).joined(separator: " ")
        #expect(arguments.contains("--setting-sources project"))
        #expect(arguments.contains("--strict-mcp-config"))
        #expect(arguments.contains("--permission-prompts host --permission-prompt-tool stdio"))
        #expect(arguments.contains("--model sonnet"))
        #expect(arguments.contains("--autocompact 150000"))
    }

    @Test func fileToolsAreAllowedOnlyInTheMemoryFolder() {
        let arguments = ClaudeProcess.arguments(model: "sonnet", memory: memory)
        #expect(arguments.joined(separator: " ").contains("--tools WebSearch,WebFetch,Read,Edit,Write --allowedTools "))
        #expect(arguments[arguments.firstIndex(of: "--allowedTools")! + 1] == "WebSearch,WebFetch,"
            + "Read(//data/App Support/memory/**),Edit(//data/App Support/memory/**),Write(//data/App Support/memory/**)")
    }

    @Test func memoryIsInTheSystemPrompt() {
        let arguments = ClaudeProcess.arguments(model: "sonnet", memory: memory)
        #expect(arguments[arguments.firstIndex(of: "--append-system-prompt")! + 1] == """
            # What you remember about the owner

            From /data/App Support/memory/MEMORY.md, when this conversation started:

            - Likes tea.
            """)
    }

    @Test func toolsThatAskFirstAreNotAllowedUpFront() {
        let write = Tool(name: "Write", activity: "Writing…", nameInInstructions: "writing files", whenToUse: nil, asksFirst: true)
        let arguments = ClaudeProcess.arguments(model: "sonnet", memory: memory, tools: [.webSearch, write]).joined(separator: " ")
        #expect(arguments.contains("--tools WebSearch,Write --allowedTools WebSearch --permission-prompts"))
        let onlyAsking = ClaudeProcess.arguments(model: "sonnet", memory: memory, tools: [write])
        #expect(!onlyAsking.contains("--allowedTools"))
    }

    @Test func claudeCodesAutoMemoryIsOff() async throws {
        let process = try ClaudeProcess(executable: try fake.write(), arguments: [], directory: fake.directory)
        var outputs = process.outputs.makeAsyncIterator()
        try process.send("autoMemory")
        _ = await nextAnswerOutput(&outputs)
        _ = await nextAnswerOutput(&outputs)
        #expect(await nextAnswerOutput(&outputs) == .event(.text("1")))
    }

    @Test func answerLinesRepeatTheRequest() {
        let request = ApprovalRequest(id: "r1", tool: "Write", detail: "note.md", input: Data(#"{"file_path":"note.md"}"#.utf8))
        #expect(String(decoding: ClaudeProcess.answerLine(to: request, allow: true), as: UTF8.self)
            == #"{"response":{"request_id":"r1","response":{"behavior":"allow","updatedInput":{"file_path":"note.md"}},"subtype":"success"},"type":"control_response"}"# + "\n")
        #expect(String(decoding: ClaudeProcess.answerLine(to: request, allow: false), as: UTF8.self)
            == #"{"response":{"request_id":"r1","response":{"behavior":"deny","message":"The owner declined."},"subtype":"success"},"type":"control_response"}"# + "\n")
    }

    /// The next output that isn't a turn's session or context size, which the fake reports before each answer.
    func nextAnswerOutput(_ outputs: inout AsyncStream<ClaudeProcess.Output>.Iterator) async -> ClaudeProcess.Output? {
        while let output = await outputs.next() {
            switch output {
            case .event(.sessionStarted), .event(.contextUsed): continue
            default: return output
            }
        }
        return nil
    }

    @Test func refusesRequestsAsideDoesNotHandle() async throws {
        let process = try ClaudeProcess(executable: try fake.write(), arguments: [], directory: fake.directory)
        var outputs = process.outputs.makeAsyncIterator()
        try process.send("unhandled")
        #expect(await nextAnswerOutput(&outputs) == .event(.textStarted))
        #expect(await nextAnswerOutput(&outputs) == .event(.text("Answer 1: ")))
        #expect(await nextAnswerOutput(&outputs) == .event(.text("Refused.")))
    }

    @Test func answersEachMessageInOneProcess() async throws {
        let process = try ClaudeProcess(executable: try fake.write(), arguments: [], directory: fake.directory)
        var outputs = process.outputs.makeAsyncIterator()
        try process.send("one")
        #expect(await nextAnswerOutput(&outputs) == .event(.textStarted))
        #expect(await nextAnswerOutput(&outputs) == .event(.text("Answer 1: ")))
        #expect(await nextAnswerOutput(&outputs) == .event(.text("one")))
        #expect(await nextAnswerOutput(&outputs) == .event(.turnEnded(error: nil)))
        try process.send("two")
        #expect(await nextAnswerOutput(&outputs) == .event(.textStarted))
        #expect(await nextAnswerOutput(&outputs) == .event(.text("Answer 2: ")))
    }

    @Test func endsWithExitStatusAndStderr() async throws {
        let script = "#!/bin/sh\necho first >&2\necho last >&2\nexit 2\n"
        let process = try ClaudeProcess(executable: try fake.write(script), arguments: [], directory: fake.directory)
        var all: [ClaudeProcess.Output] = []
        for await output in process.outputs { all.append(output) }
        #expect(all == [.exited(status: 2, stderr: "first\nlast")])
    }

    /// Answer text can hold U+2028 unescaped; it must not split the line.
    @Test func lineSeparatorInsideTextStaysInTheLine() async throws {
        let line = #"{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"a\#u{2028}b"}}}"#
        let process = try ClaudeProcess(executable: try fake.write("#!/bin/sh\ncat <<'EOF'\n\(line)\nEOF\n"), arguments: [], directory: fake.directory)
        var outputs = process.outputs.makeAsyncIterator()
        #expect(await outputs.next() == .event(.text("a\u{2028}b")))
    }

    @Test func stopEndsTheProcess() async throws {
        let process = try ClaudeProcess(executable: try fake.write(), arguments: [], directory: fake.directory)
        process.stop()
        var last: ClaudeProcess.Output?
        for await output in process.outputs { last = output }
        guard case .exited = last else { Issue.record("Expected an exit, got \(String(describing: last))"); return }
    }

    @Test func sendingToAStoppedProcessThrows() async throws {
        let process = try ClaudeProcess(executable: try fake.write("#!/bin/sh\nexit 0\n"), arguments: [], directory: fake.directory)
        for await _ in process.outputs {}
        #expect(throws: (any Error).self) { try process.send("hello") }
    }
}
