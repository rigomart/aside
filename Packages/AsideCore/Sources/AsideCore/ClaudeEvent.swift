import Foundation

/// What Aside uses from one line of `claude --output-format stream-json --include-partial-messages`.
public enum ClaudeEvent: Equatable, Sendable {
    /// A block of answer text begins. A turn that uses tools has one before and one after.
    case textStarted
    /// More answer text.
    case text(String)
    /// Claude started using a tool, such as `WebSearch`.
    case toolStarted(String)
    /// The turn is over. `error` says why it failed, if it did.
    case turnEnded(error: String?)

    /// Parses one output line. Lines Aside doesn't use (init, status, whole messages, rate limits,
    /// thinking) are nil. Decodes loosely, so a field the CLI adds or reshapes can't hide a turn's end.
    public init?(json: Data) {
        guard let line = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else { return nil }
        switch line["type"] as? String {
        case "stream_event":
            guard let event = line["event"] as? [String: Any] else { return nil }
            switch event["type"] as? String {
            case "content_block_start":
                let block = event["content_block"] as? [String: Any]
                switch block?["type"] as? String {
                case "text": self = .textStarted
                case "tool_use", "server_tool_use": self = .toolStarted(block?["name"] as? String ?? "a tool")
                default: return nil
                }
            case "content_block_delta":
                guard let delta = event["delta"] as? [String: Any], delta["type"] as? String == "text_delta",
                      let text = delta["text"] as? String
                else { return nil }
                self = .text(text)
            default:
                return nil
            }
        case "result":
            let subtype = line["subtype"] as? String
            let failed = line["is_error"] as? Bool == true || subtype != "success"
            self = .turnEnded(error: failed ? (line["result"] as? String ?? subtype ?? "Unknown error") : nil)
        default:
            return nil
        }
    }
}
