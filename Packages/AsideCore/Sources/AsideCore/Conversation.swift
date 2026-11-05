/// What the panel shows: each question with its answer as it streams in, and any errors.
public struct Conversation: Equatable, Sendable {
    public struct Exchange: Equatable, Sendable, Identifiable {
        public let id: Int
        /// Nil for an error that happened between turns, such as claude stopping while idle.
        public var question: String?
        public var answer = ""
        /// What Claude is doing when it isn't writing, such as "Searching the web…".
        public var activity: String?
        /// Cleared once the owner answers or the turn ends.
        public var approval: ApprovalRequest?
        public var error: String?
        public var isFinished = false
        /// Memory notes while answering: "Remembered: …", "Forgot: …", or "Couldn't read memory: …".
        public var memoryNotes: [String] = []
    }

    public private(set) var exchanges: [Exchange] = []

    public init() {}

    public var isEmpty: Bool { exchanges.isEmpty }

    /// Whether the last question is still being answered.
    public var isResponding: Bool { exchanges.last.map { !$0.isFinished } ?? false }

    /// Adds `question`, waiting for its answer, and returns its exchange's ID.
    @discardableResult
    public mutating func ask(_ question: String) -> Exchange.ID {
        exchanges.append(Exchange(id: exchanges.count, question: question))
        return exchanges.count - 1
    }

    public mutating func apply(_ event: ClaudeEvent) {
        guard isResponding else { return }
        let last = exchanges.count - 1
        switch event {
        case .textStarted:
            if !exchanges[last].answer.isEmpty { exchanges[last].answer += "\n\n" }
            exchanges[last].activity = nil
        case .text(let text):
            exchanges[last].answer += text
            exchanges[last].activity = nil
        case .toolStarted(let tool):
            exchanges[last].activity = Tool.activity(for: tool)
        case .approvalRequested(let request):
            exchanges[last].approval = request
        case .compacting:
            exchanges[last].activity = "Condensing the conversation…"
        case .compacted:
            exchanges[last].activity = nil
        case .unsupportedRequest, .sessionStarted, .contextUsed:
            break
        case .turnEnded(let error):
            exchanges[last].error = error
            exchanges[last].activity = nil
            exchanges[last].approval = nil
            exchanges[last].isFinished = true
        }
    }

    mutating func takeApproval() -> ApprovalRequest? {
        guard let last = exchanges.indices.last else { return nil }
        defer { exchanges[last].approval = nil }
        return exchanges[last].approval
    }

    /// Adds `notes` about memory to the newest exchange, leaving out any it already has.
    mutating func noteMemory(_ notes: [String]) {
        guard let last = exchanges.indices.last else { return }
        exchanges[last].memoryNotes += notes.filter { !exchanges[last].memoryNotes.contains($0) }
    }

    /// Ends the current answer with `message`, or adds it on its own line if nothing is being answered.
    public mutating func fail(_ message: String) {
        if !isResponding {
            exchanges.append(Exchange(id: exchanges.count))
        }
        apply(.turnEnded(error: message))
    }
}
