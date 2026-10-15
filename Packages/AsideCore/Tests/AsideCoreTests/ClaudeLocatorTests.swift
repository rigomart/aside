import Testing
@testable import AsideCore

struct ClaudeLocatorTests {
    func locator(executables: Set<String>, shell: String? = nil) -> ClaudeLocator {
        ClaudeLocator(
            homeDirectory: "/Users/me",
            isExecutable: { executables.contains($0) },
            loginShellLookup: { shell }
        )
    }

    @Test func overrideWins() {
        let found = locator(executables: ["/custom/claude", "/opt/homebrew/bin/claude"])
            .locate(override: "/custom/claude")
        #expect(found == "/custom/claude")
    }

    @Test func brokenOverrideDoesNotFallBack() {
        let found = locator(executables: ["/opt/homebrew/bin/claude"])
            .locate(override: "/missing/claude")
        #expect(found == nil)
    }

    @Test func emptyOverrideIsIgnored() {
        let found = locator(executables: ["/opt/homebrew/bin/claude"]).locate(override: "")
        #expect(found == "/opt/homebrew/bin/claude")
    }

    @Test func prefersNativeInstallOverHomebrew() {
        let found = locator(executables: ["/Users/me/.local/bin/claude", "/opt/homebrew/bin/claude"]).locate()
        #expect(found == "/Users/me/.local/bin/claude")
    }

    @Test func fallsBackToLoginShell() {
        let found = locator(executables: ["/Users/me/.volta/bin/claude"], shell: "/Users/me/.volta/bin/claude").locate()
        #expect(found == "/Users/me/.volta/bin/claude")
    }

    @Test func ignoresShellAnswerThatIsNotExecutable() {
        #expect(locator(executables: [], shell: "/nowhere/claude").locate() == nil)
    }
}
