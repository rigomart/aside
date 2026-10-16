import Foundation
import NaturalLanguage

/// What of an answer's Markdown is read aloud, and in which sentences. Formatting marks, code blocks,
/// tables and link addresses are left out; a bare web address is read as its site's name.
enum SpokenText {
    /// The spoken text of `markdown`, line for line, without blank lines. A line that is complete (a newline follows it) ends
    /// with punctuation, so a list item or heading gets a pause after it. As an answer streams in, text
    /// before its last line stays the same, so what was already said stays a prefix of this.
    static func prose(_ markdown: String) -> String {
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false)
        var spoken: [String] = []
        var inCode = false
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inCode.toggle()
                continue
            }
            guard !inCode else { continue }
            var text = speakable(trimmed)
            let isComplete = index < lines.count - 1
            guard !text.isEmpty else { continue }
            if isComplete, let last = text.last, !".!?:;".contains(last) { text += "." }
            spoken.append(text)
        }
        return spoken.joined(separator: "\n")
    }

    /// The sentences of `text` after its first `offset` characters, and the offset after the last one.
    /// The last sentence may still be growing, so it's left for later unless `includingLast`. A "sentence"
    /// with no letters or digits, such as the period a list item gets once its line ends, isn't one.
    static func sentences(in text: String, after offset: Int, includingLast: Bool) -> (sentences: [String], end: Int) {
        let rest = String(text.dropFirst(offset))
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = rest
        var ranges = tokenizer.tokens(for: rest.startIndex..<rest.endIndex)
        if !includingLast { ranges = ranges.dropLast() }
        guard let last = ranges.last else { return ([], offset) }
        let sentences = ranges.map { rest[$0].trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.contains { $0.isLetter || $0.isNumber } }
        return (sentences, offset + rest.distance(from: rest.startIndex, to: last.upperBound))
    }

    /// One line without its Markdown: no heading, quote or list marks, no emphasis or code marks,
    /// links as their text, images and tables dropped.
    private static func speakable(_ line: String) -> String {
        if line.hasPrefix("|") || line.wholeMatch(of: #/([-*_]\s*){3,}/#) != nil { return "" }
        return line
            .replacing(#/^(#{1,6}|>+|[-*+]|\d+[.)])\s+/#, with: "")
            .replacing(#/!\[[^\]]*\]\([^)]*\)/#, with: "")
            .replacing(#/\[([^\]]*)\]\([^)]*\)/#) { String($0.1) }
            .replacing(#/https?:\/\/[^\s)]+/#) { siteName(String($0.0)) }
            .replacing(#/\*+|`+|~~/#, with: "")
            // Underscores that open or close emphasis; ones inside a word, as in snake_case, stay.
            .replacing(#/(^|[^[:alnum:]])_+/#) { String($0.1) }
            .replacing(#/_+(?![[:alnum:]])/#, with: "")
    }

    /// "apple.com" for `https://www.apple.com/macos/`.
    private static func siteName(_ address: String) -> String {
        guard let host = URL(string: address)?.host() else { return "" }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
