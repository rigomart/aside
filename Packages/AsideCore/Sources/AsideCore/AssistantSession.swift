import Foundation
import Observation

/// The conversation the panel shows, and the claude process behind it. claude starts when the panel
/// opens, so it's ready by the time a question is typed. The conversation lasts until New: its claude
/// session is saved, and every claude started later resumes it. Once it grows past `compactAt` tokens,
/// a copy is compacted in the background and takes over if nothing was asked meanwhile (decision 25).
@MainActor @Observable
public final class AssistantSession {
    public enum ClaudeStatus: Equatable, Sendable {
        case searching
        case found(String)
        case missing
    }

    public static let missingMessage = "claude not found. Install Claude Code, then reopen Aside."

    public private(set) var claude = ClaudeStatus.searching
    public private(set) var conversation = Conversation()
    /// The claude session holding the conversation, saved in `<data>/session-id` so it outlasts Aside
    /// and claude. Nil after New until the first question.
    public private(set) var sessionID: String?

    @ObservationIgnored private let dataDirectory: URL
    @ObservationIgnored private let model: String
    @ObservationIgnored private let compactAt: Int
    @ObservationIgnored private let located: Task<String?, Never>
    @ObservationIgnored private let narrator: Narrator
    /// The current conversation's process. Nil before it starts and after it exits.
    @ObservationIgnored private var process: ClaudeProcess?
    @ObservationIgnored private var memoryAtLastCheck: Memory?
    @ObservationIgnored private var compaction: Compaction?
    /// Tokens the conversation took up as of the last reply.
    @ObservationIgnored private var contextTokens = 0
    /// Counts New presses, so a question still waiting for claude after New is dropped.
    @ObservationIgnored private var conversationNumber = 0

    /// A copy of the conversation compacting in the background.
    private struct Compaction {
        let copy: ClaudeProcess
        /// The session holding the compacted conversation, once compaction is done.
        var id: String?
    }

    /// - Parameters:
    ///   - dataDirectory: Where the workspace goes.
    ///   - claudePath: A configured path to claude, used instead of searching.
    ///   - speaker: Reads answers aloud.
    ///   - compactAt: Tokens past which the conversation is compacted in the background after a turn.
    public init(
        dataDirectory: URL,
        claudePath: String? = nil,
        locator: ClaudeLocator = .live,
        speaker: any Speaker,
        model: String = "sonnet",
        compactAt: Int = 80_000
    ) {
        self.dataDirectory = dataDirectory
        self.model = model
        self.compactAt = compactAt
        sessionID = (try? String(contentsOf: dataDirectory.appending(path: "session-id"), encoding: .utf8))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
        narrator = Narrator(speaker: speaker)
        let located = Task.detached { locator.locate(override: claudePath) }
        self.located = located
        Task {
            let path = await located.value
            claude = path.map(ClaudeStatus.found) ?? .missing
            Log.claude.info("claude: \(path ?? "not found", privacy: .public)")
        }
    }

    /// Call when the panel opens. Starts claude, resuming the saved conversation if there is one.
    public func prepare() {
        warmUp()
    }

    /// Whether an answer is being read aloud.
    public var isReadingAloud: Bool { narrator.isReading }

    /// While the newest answer is read aloud, where the reading is in it.
    public var caption: Caption? { narrator.caption }

    /// Asks `question` in the current conversation, and reads the answer aloud if `aloud`. Stops reading
    /// the last answer either way. Ignored while the last question is still being answered.
    public func send(_ question: String, aloud: Bool = false) {
        guard !conversation.isResponding else { return }
        let id = conversation.ask(question)
        if aloud { narrator.start(id) } else { narrator.stop() }
        // The copy wouldn't have this question; the next turn's end starts another.
        if compaction != nil { Log.claude.info("A question came in: compaction dropped") }
        discardCompaction()
        memoryAtLastCheck = readMemory() ?? memoryAtLastCheck
        let asked = conversationNumber
        Task {
            do {
                let process = try await connect()
                // New while claude was being found: the question belonged to the old conversation.
                guard conversationNumber == asked else { return }
                try process.send(question)
            } catch {
                guard conversationNumber == asked else { return }
                conversation.fail(error.localizedDescription)
                readAloud()
            }
        }
    }

    /// Answers the tool use waiting for the owner. Claude then uses the tool, or is told the owner declined.
    public func answerApproval(allow: Bool) {
        guard let request = conversation.takeApproval(), let process else { return }
        Log.claude.info("\(allow ? "Allowed" : "Denied", privacy: .public) \(request.tool, privacy: .public)")
        do {
            try process.answer(request, allow: allow)
        } catch {
            conversation.fail("Couldn't answer claude: \(error.localizedDescription)")
            readAloud()
        }
    }

    /// Stops reading the answer aloud, mid-word. The answer keeps coming in the panel.
    public func stopReadingAloud() {
        narrator.stop()
    }

    /// Clears the panel, forgets the saved session and starts a fresh claude, so the next question has
    /// no earlier context.
    public func startNewConversation() {
        narrator.stop()
        discardCompaction()
        process?.stop()
        process = nil
        conversation = Conversation()
        conversationNumber += 1
        contextTokens = 0
        save(nil)
        warmUp()
    }

    /// Starts claude in the background. A failure is logged here and shown when a question is sent.
    private func warmUp() {
        Task {
            do {
                _ = try await connect()
            } catch {
                Log.claude.error("Couldn't start claude: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// The running process, started if there isn't one.
    private func connect() async throws -> ClaudeProcess {
        if let process { return process }
        guard let path = await located.value else { throw SessionError(Self.missingMessage) }
        // Another caller may have started it while this one waited.
        if let process { return process }
        let resuming = sessionID
        let process: ClaudeProcess
        do {
            process = try launch(path, resuming: resuming)
        } catch {
            throw SessionError("Couldn't start claude: \(error.localizedDescription)")
        }
        self.process = process
        Log.claude.info("Started claude\(resuming.map { ", resuming \($0)" } ?? "", privacy: .public)")
        Task { await follow(process, resumed: resuming != nil) }
        return process
    }

    /// Starts claude in the workspace. Every claude Aside runs starts here, so all get the same flags.
    /// `resuming` continues that session; `fork` continues a copy of it under a new ID.
    /// Memory is read here, so a process started later, such as a compacted copy, has every fact saved before it.
    private func launch(_ path: String, resuming session: String?, fork: Bool = false) throws -> ClaudeProcess {
        let memory = try Memory.load(in: dataDirectory)
        let workspace = try Workspace.prepare(in: dataDirectory, memory: memory)
        var arguments = ClaudeProcess.arguments(model: model, memory: memory)
        if let session { arguments += ["--resume", session] }
        if fork { arguments += ["--fork-session"] }
        return try ClaudeProcess(executable: path, arguments: arguments, directory: workspace)
    }

    private func follow(_ process: ClaudeProcess, resumed: Bool) async {
        // A resume that fails exits before any turn begins.
        var began = false
        for await output in process.outputs {
            if process === compaction?.copy {
                compacting(output)
                continue
            }
            // A process stopped for a new conversation, or replaced by its compacted copy, no longer
            // speaks for the panel.
            guard process === self.process else { return }
            if !output.isAnswerText { noteMemoryChanges() }
            switch output {
            case .event(let event):
                conversation.apply(event)
                readAloud()
                switch event {
                case .sessionStarted(let id):
                    began = true
                    save(id)
                case .contextUsed(let tokens):
                    contextTokens = tokens
                case .compacting:
                    Log.claude.error("Claude Code's own autocompact is running at \(self.contextTokens) tokens")
                case .turnEnded(let error):
                    Log.claude.info("Turn ended at \(self.contextTokens) tokens\(error.map { ": \($0)" } ?? "", privacy: .public)")
                    compactIfNeeded()
                default:
                    break
                }
            case .exited(let status, let stderr):
                self.process = nil
                discardCompaction()
                Log.claude.error("claude exited with status \(status): \(stderr, privacy: .public)")
                let detail = stderr.split(whereSeparator: \.isNewline).last.map { ": \($0)" } ?? ""
                let resumeFailed = resumed && !began
                if resumeFailed { save(nil) }
                let next = sessionID == nil ? "starts a new conversation" : "continues the conversation"
                conversation.fail("\(resumeFailed ? "Couldn't continue the conversation" : "claude stopped") (exit status \(status))\(detail). Your next question \(next).")
                readAloud()
            }
        }
    }

    /// Shows what claude saved to or removed from memory since the last check.
    private func noteMemoryChanges() {
        guard let current = readMemory() else { return }
        if let earlier = memoryAtLastCheck { conversation.noteMemory(current.changes(since: earlier)) }
        memoryAtLastCheck = current
    }

    /// The memory file now, or nil after the panel says why it couldn't be read.
    private func readMemory() -> Memory? {
        do {
            return try Memory.load(in: dataDirectory)
        } catch {
            Log.claude.error("Couldn't read memory: \(error.localizedDescription, privacy: .public)")
            conversation.noteMemory(["Couldn't read memory: \(error.localizedDescription)"])
            return nil
        }
    }

    /// After a turn, past `compactAt` tokens: starts a copy of the conversation that compacts itself in
    /// the background, while this process keeps answering.
    private func compactIfNeeded() {
        guard compaction == nil, contextTokens >= compactAt, let sessionID, case .found(let path) = claude else { return }
        let copy: ClaudeProcess
        do {
            copy = try launch(path, resuming: sessionID, fork: true)
        } catch {
            Log.claude.error("Couldn't start compacting: \(error.localizedDescription, privacy: .public)")
            return
        }
        compaction = Compaction(copy: copy)
        Log.claude.info("Compacting \(self.contextTokens) tokens in the background")
        Task { await follow(copy, resumed: false) }
        do {
            try copy.send("/compact")
        } catch {
            Log.claude.error("Couldn't start compacting: \(error.localizedDescription, privacy: .public)")
            discardCompaction()
        }
    }

    /// What the compacting copy reports. When it finishes it replaces the live process, which is idle
    /// because a question sent meanwhile would have discarded the copy. A failure is only logged; the
    /// next turn's end tries again.
    private func compacting(_ output: ClaudeProcess.Output) {
        guard let compaction else { return }
        switch output {
        case .event(.compacted(let id)):
            self.compaction?.id = id
        case .event(.turnEnded(let error)):
            self.compaction = nil
            guard error == nil, let id = compaction.id else {
                Log.claude.error("Compaction failed: \(error ?? "no compacted session", privacy: .public)")
                compaction.copy.stop()
                return
            }
            process?.stop()
            process = compaction.copy
            contextTokens = 0
            save(id)
            Log.claude.info("Compacted: session \(id, privacy: .public) took over")
        case .exited(let status, let stderr):
            self.compaction = nil
            Log.claude.error("Compaction exited with status \(status): \(stderr, privacy: .public)")
        default:
            break
        }
    }

    private func discardCompaction() {
        compaction?.copy.stop()
        compaction = nil
    }

    /// Saves `id` as the conversation's session, or forgets the saved one. Called at every turn's start,
    /// so a failed write is retried then and only logged.
    private func save(_ id: String?) {
        sessionID = id
        let file = dataDirectory.appending(path: "session-id")
        do {
            if let id {
                try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
                try (id + "\n").write(to: file, atomically: true, encoding: .utf8)
            } else if FileManager.default.fileExists(atPath: file.path) {
                try FileManager.default.removeItem(at: file)
            }
        } catch {
            Log.claude.error("Couldn't save the session: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Hands the newest answer to the narrator, which reads it if it was asked aloud.
    private func readAloud() {
        if let last = conversation.exchanges.last { narrator.follow(last) }
    }
}

private extension ClaudeProcess.Output {
    var isAnswerText: Bool {
        if case .event(.text) = self { true } else { false }
    }
}

struct SessionError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}
