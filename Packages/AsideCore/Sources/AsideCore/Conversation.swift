/// What the panel shows: each question with its answer as it streams in, and any errors.
public struct Conversation: Equatable, Sendable {
    public struct Exchange: Equatable, Sendable, Identifiable {
        public let id: Int
        /// Nil for an error that happened between turns, such as claude stopping while idle.
        public var question: String?
        public var answer = ""
        /// What Claude is doing when it isn't writing, such as "Searching the web…".
        public var activity: String?
        public var error: String?
        public var isFinished = false
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
            exchanges[last].activity = Self.activity(for: tool)
        case .turnEnded(let error):
            exchanges[last].error = error
            exchanges[last].activity = nil
            exchanges[last].isFinished = true
        }
    }

    /// Ends the current answer with `message`, or adds it on its own line if nothing is being answered.
    public mutating func fail(_ message: String) {
        if !isResponding {
            exchanges.append(Exchange(id: exchanges.count))
        }
        apply(.turnEnded(error: message))
    }

    static func activity(for tool: String) -> String {
        switch tool {
        case "WebSearch": "Searching the web…"
        case "WebFetch": "Reading a web page…"
        default: "Using \(tool)…"
        }
    }
}
