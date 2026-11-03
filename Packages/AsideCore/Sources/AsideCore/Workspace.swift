import Foundation

/// The folder claude runs in. Its CLAUDE.md sets the assistant's voice. Aside rewrites it each time
/// claude starts, so the file always matches the app.
public enum Workspace {
    /// Creates `<dataDirectory>/workspace/` with its CLAUDE.md and returns it.
    public static func prepare(in dataDirectory: URL) throws -> URL {
        let workspace = dataDirectory.appending(path: "workspace", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        try instructions().write(to: workspace.appending(path: "CLAUDE.md"), atomically: true, encoding: .utf8)
        return workspace
    }

    static func instructions(tools: [Tool] = Tool.all) -> String {
        let names = tools.map(\.nameInInstructions).formatted(.list(type: .and).locale(Locale(identifier: "en_US")))
        let rules = [
            "Answer in a few sentences. Lead with the answer. No preamble, no offers to help further.",
            "Write plain prose that reads well aloud. No headings, tables, or code blocks unless asked.",
        ] + tools.compactMap(\.whenToUse) + [
            "You can't see their screen or files. Your only tools are \(names).",
        ]
        return """
            # Aside

            You are Aside, a personal assistant in a small floating panel on the owner's Mac. They open it \
            with a hotkey while working in another app, ask something, and go back to what they were doing.

            \(rules.map { "- \($0)" }.joined(separator: "\n"))

            """
    }
}
