import XCTest

/// Asking and answering, against `fake-claude` so answers are exact and no subscription is used.
final class ConversationTests: VerifyTestCase {
    /// A question typed over another app is answered in the panel, a follow-up reaches the same claude,
    /// and Command-N starts a new conversation with a fresh one.
    @MainActor func testAnswersFollowUpsAndNewConversation() {
        let app = launch(claude: Self.fakeClaude)
        let calculator = launchFrontApp()
        let panel = pressHotkey(over: calculator, in: app)

        ask("What is \(stamp)?", in: app)
        waitForValue("Answer 1: What is \(stamp)?", of: app.answers.element(boundBy: 0))
        XCTAssertEqual(app.questions.element(boundBy: 0).value as? String, "What is \(stamp)?")
        XCTAssertEqual(app.askField.value as? String, "", "Sending should clear the field")
        XCTAssertEqual(calculator.state, .runningForeground, "Calculator should stay the active app")
        shot("answered", of: panel)

        ask("And \(stamp)?", in: app)
        waitForValue("Answer 2: And \(stamp)?", of: app.answers.element(boundBy: 1))
        shot("follow-up", of: panel)

        app.askField.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(app.answers.firstMatch.waitForNonExistence(timeout: 5), "Command-N did not clear the panel")
        ask("Fresh \(stamp)?", in: app)
        waitForValue("Answer 1: Fresh \(stamp)?", of: app.answers.element(boundBy: 0))
        XCTAssertEqual(app.answers.count, 1)
        shot("new-conversation", of: panel)
    }

    /// When claude dies mid-answer, the panel says so, and the next question starts over.
    @MainActor func testClaudeStoppingShowsInPanel() {
        let app = launch(claude: Self.fakeClaude)
        let panel = openPanelWithURL(app)

        ask("Go boom \(stamp)", in: app)
        waitForValue("claude stopped (exit status 3): something broke. Your next question starts a new conversation.",
                     of: app.errors.element(boundBy: 0))
        shot("stopped", of: panel)

        ask("After \(stamp)?", in: app)
        waitForValue("Answer 1: After \(stamp)?", of: app.answers.element(boundBy: 0))
        shot("started-over", of: panel)
    }

    /// With claude missing, the status line says so, and asking shows the same message instead of hanging.
    @MainActor func testMissingClaudeShowsInPanel() {
        let app = launch(claude: "/nonexistent/claude")
        let panel = openPanelWithURL(app)
        let missing = "claude not found. Install Claude Code, then reopen Aside."
        waitForValue(missing, of: app.claudeStatus)

        ask("Hello \(stamp)?", in: app)
        waitForValue(missing, of: app.errors.element(boundBy: 0))
        shot("missing", of: panel)
    }
}
