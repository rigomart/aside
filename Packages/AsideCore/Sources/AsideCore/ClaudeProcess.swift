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
    /// none of the owner's MCP servers, and only the web tools exist. Anything that would ask for
    /// permission is denied until the panel can ask (M4).
    public static func arguments(model: String) -> [String] {
        [
            "-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
            "--include-partial-messages", "--model", model,
            "--setting-sources", "project", "--strict-mcp-config",
            "--tools", "WebSearch,WebFetch", "--allowedTools", "WebSearch,WebFetch",
            "--permission-prompts", "none",
        ]
    }

    /// One user message as a line of stream-json input.
    public static func inputLine(_ text: String) -> Data {
        let message = ["type": "user", "message": ["role": "user", "content": text]] as [String: Any]
        // Serializing a dictionary of strings can't fail.
        var line = try! JSONSerialization.data(withJSONObject: message, options: [.sortedKeys, .withoutEscapingSlashes])
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
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        let (exits, exited) = AsyncStream.makeStream(of: Int32.self)
        process.terminationHandler = { exited.yield($0.terminationStatus); exited.finish() }
        try process.run()

        let (outputs, output) = AsyncStream.makeStream(of: Output.self)
        Task.detached {
            async let errors = Self.tail(of: Self.chunks(of: stderr.fileHandleForReading))
            // Split on newlines only: answer text may hold U+2028, which `lines` APIs also split on.
            var buffer = Data()
            for await chunk in Self.chunks(of: stdout.fileHandleForReading) {
                buffer.append(chunk)
                while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                    if let event = ClaudeEvent(json: buffer[..<newline]) { output.yield(.event(event)) }
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
        self.input = stdin.fileHandleForWriting
    }

    /// Sends a user message. Throws if the process has stopped reading.
    public func send(_ text: String) throws {
        try input.write(contentsOf: Self.inputLine(text))
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
