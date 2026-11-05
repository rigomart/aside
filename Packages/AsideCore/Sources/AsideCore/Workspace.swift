import Foundation

/// The folder claude runs in. Its CLAUDE.md sets the assistant's voice and how it keeps its memory.
/// Aside rewrites it each time claude starts, so the file always matches the app.
public enum Workspace {
    /// Creates `<dataDirectory>/workspace/` with its CLAUDE.md and returns it.
    public static func prepare(in dataDirectory: URL, memory: Memory) throws -> URL {
        let workspace = dataDirectory.appending(path: "workspace", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        try instructions(memory: memory.file).write(to: workspace.appending(path: "CLAUDE.md"), atomically: true, encoding: .utf8)
        return workspace
    }

    static func instructions(memory: URL, tools: [Tool] = Tool.all) -> String {
        let uniqueNames = tools.map(\.nameInInstructions).reduce(into: [String]()) { names, name in
            if !names.contains(name) { names.append(name) }
        }
        let list = uniqueNames.formatted(.list(type: .and).locale(Locale(identifier: "en_US")))
        let rules = [
            "Answer in a few sentences. Lead with the answer. No preamble, no offers to help further.",
            "Write plain prose that reads well aloud. No headings, tables, or code blocks unless asked.",
        ] + tools.compactMap(\.whenToUse) + [
            "Your memory file is \(memory.path): one fact per line, each starting with \"- \". What it held when this conversation started is in your system prompt.",
            "Save lasting facts about the owner as you learn them, without asking: preferences, people, projects, plans. Save anything they ask you to remember. Skip passing details of the question at hand.",
            "To save, Read the file, then Edit it. Write each fact as a short sentence to the owner, such as \"You're vegetarian.\", and change an outdated line rather than adding one that contradicts it. When they ask you to forget something, remove its line.",
            "The panel shows the owner each fact you save or remove. Don't mention saving in your answer unless they asked you to remember or forget something.",
            "You can't see their screen or files. Your only tools are \(list). Use the file tools only on your memory file.",
        ]
        return """
            # Aside

            You are Aside, a personal assistant in a small floating panel on the owner's Mac. They open it \
            with a hotkey while working in another app, ask something, and go back to what they were doing.

            \(rules.map { "- \($0)" }.joined(separator: "\n"))

            """
    }
}
