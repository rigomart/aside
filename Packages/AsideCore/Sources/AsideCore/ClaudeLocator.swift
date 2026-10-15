import Foundation

/// Finds the `claude` executable. GUI apps don't inherit the shell's PATH, so this checks
/// the usual install locations first, then asks the user's login shell.
public struct ClaudeLocator: Sendable {
    public var homeDirectory: String
    public var isExecutable: @Sendable (String) -> Bool
    public var loginShellLookup: @Sendable () -> String?

    public init(
        homeDirectory: String,
        isExecutable: @escaping @Sendable (String) -> Bool,
        loginShellLookup: @escaping @Sendable () -> String?
    ) {
        self.homeDirectory = homeDirectory
        self.isExecutable = isExecutable
        self.loginShellLookup = loginShellLookup
    }

    public static let live = ClaudeLocator(
        homeDirectory: NSHomeDirectory(),
        isExecutable: { FileManager.default.isExecutableFile(atPath: $0) },
        loginShellLookup: lookUpInLoginShell
    )

    /// Returns the path to `claude`, or nil if it can't be found. A non-empty `override`
    /// (a path the user configured) is used as is: if it isn't executable, the result is nil
    /// rather than some other install.
    public func locate(override: String? = nil) -> String? {
        if let override, !override.isEmpty {
            return isExecutable(override) ? override : nil
        }
        if let path = candidates.first(where: isExecutable) {
            return path
        }
        if let path = loginShellLookup(), isExecutable(path) {
            return path
        }
        return nil
    }

    var candidates: [String] {
        [
            "\(homeDirectory)/.local/bin/claude",
            "\(homeDirectory)/.claude/local/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
        ]
    }
}

/// Runs `command -v claude` in the user's interactive login shell, so PATH changes in
/// both profile and rc files apply. Blocks until the shell exits: call it off the main actor.
@Sendable private func lookUpInLoginShell() -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh")
    process.arguments = ["-l", "-i", "-c", "command -v claude"]
    let output = Pipe()
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    process.standardInput = FileHandle.nullDevice
    do {
        try process.run()
    } catch {
        return nil
    }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { return nil }
    // Shell startup files can print their own lines; the answer is the last absolute path.
    return String(decoding: data, as: UTF8.self)
        .split(whereSeparator: \.isNewline)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .last { $0.hasPrefix("/") }
}
