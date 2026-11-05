/// A tool claude can use in Aside. `Tool.all` feeds claude's flags, the panel's activity line and the
/// workspace instructions.
public struct Tool: Sendable {
    /// claude's name for the tool, as in `--tools` and in the stream.
    public let name: String
    /// What the panel says while claude uses it.
    public let activity: String
    let nameInInstructions: String
    let whenToUse: String?
    /// Whether each use waits for the owner to allow it in the panel.
    public let asksFirst: Bool
    /// Whether claude may use it without asking inside Aside's memory folder. Elsewhere `asksFirst` applies.
    var allowedInMemory = false

    static let webSearch = Tool(
        name: "WebSearch", activity: "Searching the web…", nameInInstructions: "web search",
        whenToUse: "Search the web for anything current: news, prices, schedules, versions, opening hours.",
        asksFirst: false
    )
    static let webFetch = Tool(
        name: "WebFetch", activity: "Reading a web page…", nameInInstructions: "reading web pages",
        whenToUse: nil, asksFirst: false
    )

    // Claude Code's Edit and Write fail on a file it hasn't Read, so Read is here too.
    static let read = Tool(
        name: "Read", activity: "Checking memory…", nameInInstructions: "your memory file",
        whenToUse: nil, asksFirst: true, allowedInMemory: true
    )
    static let edit = Tool(
        name: "Edit", activity: "Remembering…", nameInInstructions: "your memory file",
        whenToUse: nil, asksFirst: true, allowedInMemory: true
    )
    static let write = Tool(
        name: "Write", activity: "Remembering…", nameInInstructions: "your memory file",
        whenToUse: nil, asksFirst: true, allowedInMemory: true
    )

    public static let all: [Tool] = [webSearch, webFetch, read, edit, write]

    static func activity(for name: String) -> String {
        all.first { $0.name == name }?.activity ?? "Using \(name)…"
    }
}
