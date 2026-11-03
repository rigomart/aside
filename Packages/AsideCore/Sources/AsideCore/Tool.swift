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

    static let webSearch = Tool(
        name: "WebSearch", activity: "Searching the web…", nameInInstructions: "web search",
        whenToUse: "Search the web for anything current: news, prices, schedules, versions, opening hours.",
        asksFirst: false
    )
    static let webFetch = Tool(
        name: "WebFetch", activity: "Reading a web page…", nameInInstructions: "reading web pages",
        whenToUse: nil, asksFirst: false
    )

    public static let all: [Tool] = [webSearch, webFetch]

    static func activity(for name: String) -> String {
        all.first { $0.name == name }?.activity ?? "Using \(name)…"
    }
}
