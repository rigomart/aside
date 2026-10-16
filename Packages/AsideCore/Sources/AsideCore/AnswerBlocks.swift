/// An answer's Markdown split into the blocks the panel formats: paragraphs, headings, list items and
/// code. Inline marks (bold, links, code spans) stay in the text for the panel to render. Tables show
/// as code, so their columns line up.
public enum AnswerBlock: Equatable, Sendable {
    case paragraph(String)
    case heading(String)
    /// `marker` is "•" for a bulleted item, or the item's number, as in "2.".
    case item(marker: String, text: String)
    case code(String)

    /// The blocks of `markdown`. An answer still streaming in may end inside a code block; what has
    /// arrived of it shows as code.
    public static func blocks(_ markdown: String) -> [AnswerBlock] {
        var blocks: [AnswerBlock] = []
        var paragraph: [Substring] = []
        var code: [Substring]?
        var table: [Substring] = []

        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: "\n"))) }
            if !table.isEmpty { blocks.append(.code(table.joined(separator: "\n"))) }
            paragraph = []
            table = []
        }

        for line in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingPrefix(while: \.isWhitespace)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                if let lines = code {
                    blocks.append(.code(lines.joined(separator: "\n")))
                    code = nil
                } else {
                    flush()
                    code = []
                }
            } else if code != nil {
                code?.append(line)
            } else if trimmed.hasPrefix("|") {
                if !paragraph.isEmpty { flush() }
                table.append(trimmed)
            } else if trimmed.isEmpty {
                flush()
            } else if let match = trimmed.wholeMatch(of: /#{1,6}\s+(.*)/) {
                flush()
                blocks.append(.heading(String(match.1)))
            } else if trimmed.wholeMatch(of: /([-*_]\s*){3,}/) != nil {
                flush()
            } else if let match = trimmed.wholeMatch(of: /[-*+]\s+(.*)/) {
                flush()
                blocks.append(.item(marker: "•", text: String(match.1)))
            } else if let match = trimmed.wholeMatch(of: /(\d+)[.)]\s+(.*)/) {
                flush()
                blocks.append(.item(marker: "\(match.1).", text: String(match.2)))
            } else {
                if !table.isEmpty { flush() }
                paragraph.append(trimmed)
            }
        }
        flush()
        if let code { blocks.append(.code(code.joined(separator: "\n"))) }
        return blocks
    }
}
