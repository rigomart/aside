import Foundation
import Testing
@testable import AsideCore

struct ClaudeProcessTests {
    let fake = FakeClaude()

    @Test func inputLineIsOneStreamJSONUserMessage() {
        let line = String(decoding: ClaudeProcess.inputLine(#"Say "hi" / bye"#), as: UTF8.self)
        #expect(line == #"{"message":{"content":"Say \"hi\" / bye","role":"user"},"type":"user"}"# + "\n")
    }

    @Test func argumentsKeepTheOwnersSetupOut() {
        let arguments = ClaudeProcess.arguments(model: "sonnet").joined(separator: " ")
        #expect(arguments.contains("--setting-sources project"))
        #expect(arguments.contains("--strict-mcp-config"))
        #expect(arguments.contains("--tools WebSearch,WebFetch"))
        #expect(arguments.contains("--model sonnet"))
    }

    @Test func answersEachMessageInOneProcess() async throws {
        let process = try ClaudeProcess(executable: try fake.write(), arguments: [], directory: fake.directory)
        var outputs = process.outputs.makeAsyncIterator()
        try process.send("one")
        #expect(await outputs.next() == .event(.textStarted))
        #expect(await outputs.next() == .event(.text("Answer 1: ")))
        #expect(await outputs.next() == .event(.text("one")))
        #expect(await outputs.next() == .event(.turnEnded(error: nil)))
        try process.send("two")
        #expect(await outputs.next() == .event(.textStarted))
        #expect(await outputs.next() == .event(.text("Answer 2: ")))
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
