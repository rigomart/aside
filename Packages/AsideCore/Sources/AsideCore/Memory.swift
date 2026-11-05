import Foundation

/// What Aside remembers about the owner: `<data>/memory/MEMORY.md`, one fact per line starting with "- ".
/// claude edits it with its file tools while it works, and each new claude starts with it in its system prompt.
/// The owner can edit it by hand.
public struct Memory: Equatable, Sendable {
    public let directory: URL
    /// MEMORY.md as it was read.
    public let text: String

    static let header = """
        # Memory

        What Aside remembers about you, one fact per line. You can edit this file.


        """

    /// Reads `<dataDirectory>/memory/MEMORY.md`, creating the folder and the file if they're missing.
    public static func load(in dataDirectory: URL) throws -> Memory {
        let directory = dataDirectory.appending(path: "memory", directoryHint: .isDirectory)
        let file = file(in: directory)
        if !FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try header.write(to: file, atomically: true, encoding: .utf8)
        }
        return Memory(directory: directory, text: try String(contentsOf: file, encoding: .utf8))
    }

    static func file(in directory: URL) -> URL { directory.appending(path: "MEMORY.md") }

    public var file: URL { Self.file(in: directory) }

    /// The facts, without their "- ".
    var facts: [String] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            line.hasPrefix("- ") ? line.dropFirst(2).trimmingCharacters(in: .whitespaces) : nil
        }
    }

    /// For `--append-system-prompt`: the facts as they are when claude starts.
    var prompt: String {
        let facts = facts.map { "- \($0)" }.joined(separator: "\n")
        return """
            # What you remember about the owner

            From \(file.path), when this conversation started:

            \(facts.isEmpty ? "Nothing yet." : facts)
            """
    }

    /// What the panel says about the facts saved and removed since `earlier`: "Remembered: …", "Forgot: …".
    func changes(since earlier: Memory) -> [String] {
        let before = Set(earlier.facts), after = Set(facts)
        return earlier.facts.filter { !after.contains($0) }.map { "Forgot: \($0)" }
            + facts.filter { !before.contains($0) }.map { "Remembered: \($0)" }
    }
}
