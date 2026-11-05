import Foundation

/// One running `claude` that holds one conversation. Each `send` is a user message on stdin;
/// `outputs` yields what comes back, and ends with `.exited` once the process is gone.
public final class ClaudeProcess: Sendable {
    public enum Output: Equatable, Sendable {
        case event(ClaudeEvent)
        /// The process ended. `stderr` holds the last lines it wrote there.
        case exited(status: Int32, stderr: String)
    }

    /// Flags for a conversation in Aside's workspace. Only the workspace's own settings and CLAUDE.md load,
    /// none of the owner's MCP servers, and only `tools` exist. Tools that don't ask first are allowed
    /// up front, and so are the `allowedInMemory` tools inside `memory.directory`; claude asks Aside on stdout before
    /// using any other, and waits for `answer`. `memory` goes in the system prompt.
    public static func arguments(model: String, memory: Memory, tools: [Tool] = Tool.all) -> [String] {
        // A rule's path starts with "//" when it's absolute; a single "/" would be relative to the settings file.
        let allowed = tools.filter { !$0.asksFirst }.map(\.name)
            + tools.filter(\.allowedInMemory).map { "\($0.name)(/\(memory.directory.path)/**)" }
        return [
            "-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
            "--include-partial-messages", "--model", model,
            "--setting-sources", "project", "--strict-mcp-config",
            "--tools", tools.map(\.name).joined(separator: ","),
        ] + (allowed.isEmpty ? [] : ["--allowedTools", allowed.joined(separator: ",")]) + [
            "--permission-prompts", "host", "--permission-prompt-tool", "stdio",
            "--append-system-prompt", memory.prompt,
            // A backstop for Aside's own background compaction (decision 25).
            "--autocompact", "150000",
        ]
    }

    /// Added to Aside's own environment for claude. Claude Code's auto memory is off: Aside keeps its own
    /// (`Memory`), and the owner's Claude Code memory stays untouched.
    static let environment = ["CLAUDE_CODE_DISABLE_AUTO_MEMORY": "1"]

    /// One user message as a line of stream-json input.
    public static func inputLine(_ text: String) -> Data {
        line(["type": "user", "message": ["role": "user", "content": text]])
    }

    /// The owner's answer to `request`. A denied tool gets a message claude sees as the tool's result.
    public static func answerLine(to request: ApprovalRequest, allow: Bool) -> Data {
        let decision: [String: Any] = allow
            ? ["behavior": "allow", "updatedInput": (try? JSONSerialization.jsonObject(with: request.input)) ?? [:]]
            : ["behavior": "deny", "message": "The owner declined."]
        return line(["type": "control_response", "response": ["subtype": "success", "request_id": request.id, "response": decision]])
    }

    static func refusalLine(to id: String, kind: String) -> Data {
        line(["type": "control_response", "response": ["subtype": "error", "request_id": id, "error": "Aside doesn't handle \(kind) requests."]])
    }

    private static func line(_ object: [String: Any]) -> Data {
        var line = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        line.append(UInt8(ascii: "\n"))
        return line
    }

    public let outputs: AsyncStream<Output>
    private let process: Process
    private let input: FileHandle

    /// Starts `executable` in `directory`. Throws if it can't be launched.
    public init(executable: String, arguments: [String], directory: URL) throws {
        // A write to a process that just died would raise SIGPIPE and kill Aside; ignored, it throws instead.
        signal(SIGPIPE, SIG_IGN)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.environment = ProcessInfo.processInfo.environment.merging(Self.environment) { $1 }
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        let (exits, exited) = AsyncStream.makeStream(of: Int32.self)
        process.terminationHandler = { exited.yield($0.terminationStatus); exited.finish() }
        try process.run()

        let (outputs, output) = AsyncStream.makeStream(of: Output.self)
        let input = stdin.fileHandleForWriting
        Task.detached {
            async let errors = Self.tail(of: Self.chunks(of: stderr.fileHandleForReading))
            // Split on newlines only: answer text may hold U+2028, which `lines` APIs also split on.
            var buffer = Data()
            for await chunk in Self.chunks(of: stdout.fileHandleForReading) {
                buffer.append(chunk)
                while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                    switch ClaudeEvent(json: buffer[..<newline]) {
                    case .unsupportedRequest(let id, let kind):
                        Log.claude.error("Refused a \(kind, privacy: .public) request from claude")
                        try? input.write(contentsOf: Self.refusalLine(to: id, kind: kind))
                    case let event?: output.yield(.event(event))
                    case nil: break
                    }
                    buffer.removeSubrange(...newline)
                }
            }
            var status: Int32 = -1
            for await code in exits { status = code }
            output.yield(.exited(status: status, stderr: await errors))
            output.finish()
        }
        self.outputs = outputs
        self.process = process
        self.input = input
    }

    /// Sends a user message. Throws if the process has stopped reading.
    public func send(_ text: String) throws {
        try input.write(contentsOf: Self.inputLine(text))
    }

    /// Answers a request for the owner's approval. Throws if the process has stopped reading.
    public func answer(_ request: ApprovalRequest, allow: Bool) throws {
        try input.write(contentsOf: Self.answerLine(to: request, allow: allow))
    }

    /// Ends the process. `outputs` still finishes with `.exited`.
    public func stop() {
        try? input.close()
        if process.isRunning { process.terminate() }
    }

    /// What `handle` delivers, as it arrives, until end of file. `FileHandle.bytes` would hold
    /// a pipe's output back until its buffer fills, so an answer wouldn't stream.
    private static func chunks(of handle: FileHandle) -> AsyncStream<Data> {
        AsyncStream { continuation in
            handle.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    continuation.finish()
                } else {
                    continuation.yield(data)
                }
            }
        }
    }

    /// The last `count` lines of `chunks`.
    private static func tail(of chunks: AsyncStream<Data>, count: Int = 20) async -> String {
        var data = Data()
        for await chunk in chunks {
            data.append(chunk)
            if data.count > 16_384 { data = data.suffix(8_192) }
        }
        return String(decoding: data, as: UTF8.self)
            .split(whereSeparator: \.isNewline).suffix(count).joined(separator: "\n")
    }
}
