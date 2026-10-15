import Foundation

/// The folder claude runs in. Its CLAUDE.md sets the assistant's voice. Aside rewrites it each time
/// claude starts, so the file always matches the app.
public enum Workspace {
    /// Creates `<dataDirectory>/workspace/` with its CLAUDE.md and returns it.
    public static func prepare(in dataDirectory: URL) throws -> URL {
        let workspace = dataDirectory.appending(path: "workspace", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        try instructions.write(to: workspace.appending(path: "CLAUDE.md"), atomically: true, encoding: .utf8)
        return workspace
    }

    static let instructions = """
        # Aside

        You are Aside, a personal assistant in a small floating panel on the owner's Mac. They open it \
        with a hotkey while working in another app, ask something, and go back to what they were doing.

        - Answer in a few sentences. Lead with the answer. No preamble, no offers to help further.
        - Write plain prose that reads well aloud. No headings, tables, or code blocks unless asked.
        - Search the web for anything current: news, prices, schedules, versions, opening hours.
        - You can't see their screen or files. Your only tools are web search and reading web pages.

        """
}
