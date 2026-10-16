import Foundation
import Observation

/// The conversation the panel shows, and the claude process behind it. claude starts when the panel
/// opens, so it's ready by the time a question is typed; one process holds the whole conversation.
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

    @ObservationIgnored private let dataDirectory: URL
    @ObservationIgnored private let model: String
    @ObservationIgnored private let idleLimit: TimeInterval
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let located: Task<String?, Never>
    @ObservationIgnored private let narrator: Narrator
    /// The current conversation's process. Nil before it starts and after it exits.
    @ObservationIgnored private var process: ClaudeProcess?
    @ObservationIgnored private var lastActivity: Date?

    /// - Parameters:
    ///   - dataDirectory: Where the workspace goes.
    ///   - claudePath: A configured path to claude, used instead of searching.
    ///   - speaker: Reads answers aloud.
    ///   - idleLimit: Seconds without a question or answer after which opening the panel starts a new conversation.
    public init(
        dataDirectory: URL,
        claudePath: String? = nil,
        locator: ClaudeLocator = .live,
        speaker: any Speaker,
        model: String = "sonnet",
        idleLimit: TimeInterval = 600,
        now: @escaping () -> Date = Date.init
    ) {
        self.dataDirectory = dataDirectory
        self.model = model
        self.idleLimit = idleLimit
        self.now = now
        narrator = Narrator(speaker: speaker)
        let located = Task.detached { locator.locate(override: claudePath) }
        self.located = located
        Task {
            let path = await located.value
            claude = path.map(ClaudeStatus.found) ?? .missing
            Log.claude.info("claude: \(path ?? "not found", privacy: .public)")
        }
    }

    /// Call when the panel opens. Ends a conversation that sat idle past the limit, and starts claude.
    public func prepare() {
        if let lastActivity, !conversation.isResponding, now().timeIntervalSince(lastActivity) > idleLimit {
            Log.claude.info("Idle past the limit: new conversation")
            startNewConversation()
        } else {
            warmUp()
        }
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
        lastActivity = now()
        Task {
            do {
                try await connect().send(question)
            } catch {
                conversation.fail(error.localizedDescription)
                readAloud()
            }
        }
    }

    /// Stops reading the answer aloud, mid-word. The answer keeps coming in the panel.
    public func stopReadingAloud() {
        narrator.stop()
    }

    /// Clears the panel and starts a fresh claude, so the next question has no earlier context.
    public func startNewConversation() {
        narrator.stop()
        process?.stop()
        process = nil
        conversation = Conversation()
        lastActivity = nil
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
        let process: ClaudeProcess
        do {
            let workspace = try Workspace.prepare(in: dataDirectory)
            process = try ClaudeProcess(executable: path, arguments: ClaudeProcess.arguments(model: model), directory: workspace)
        } catch {
            throw SessionError("Couldn't start claude: \(error.localizedDescription)")
        }
        self.process = process
        Log.claude.info("Started claude")
        Task { await follow(process) }
        return process
    }

    private func follow(_ process: ClaudeProcess) async {
        for await output in process.outputs {
            // A process stopped for a new conversation no longer speaks for the panel.
            guard process === self.process else { return }
            switch output {
            case .event(let event):
                conversation.apply(event)
                readAloud()
                if case .turnEnded(let error) = event {
                    lastActivity = now()
                    Log.claude.info("Turn ended\(error.map { ": \($0)" } ?? "", privacy: .public)")
                }
            case .exited(let status, let stderr):
                self.process = nil
                Log.claude.error("claude exited with status \(status): \(stderr, privacy: .public)")
                // Even a clean exit loses the conversation's context, so it always shows.
                let detail = stderr.split(whereSeparator: \.isNewline).last.map { ": \($0)" } ?? ""
                conversation.fail("claude stopped (exit status \(status))\(detail). Your next question starts a new conversation.")
                readAloud()
            }
        }
    }

    /// Hands the newest answer to the narrator, which reads it if it was asked aloud.
    private func readAloud() {
        if let last = conversation.exchanges.last { narrator.follow(last) }
    }
}

struct SessionError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}
