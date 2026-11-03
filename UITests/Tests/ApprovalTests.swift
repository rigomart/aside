import XCTest

/// A tool that asks first, against `fake-claude`, whose "approve" question asks to write note.md and
/// answers with what Aside replied.
final class ApprovalTests: VerifyTestCase {
    /// The request shows in the answer card, Return in the field doesn't answer it, and Allow lets claude go on.
    @MainActor func testAllowLetsClaudeUseTheTool() {
        let app = launch(claude: Self.fakeClaude)
        let panel = openPanelWithURL(app)

        ask("Please approve \(stamp)", in: app)
        waitForValue("Allow Write?", of: app.approval)
        XCTAssertEqual(app.approvalDetail.value as? String, "note.md")
        shot("asking", of: panel)

        ask("More \(stamp)", in: app)
        XCTAssertTrue(app.approval.exists, "Return in the field should not answer the request")
        XCTAssertEqual(app.askField.value as? String, "More \(stamp)", "A question sent while asking keeps its text")

        app.allowButton.click()
        waitForValue("Answer 1: Allowed: wrote note.md.", of: app.answers.element(boundBy: 0))
        XCTAssertFalse(app.approval.exists)
        shot("allowed", of: panel)
    }

    /// Deny tells claude the owner declined, and claude's answer says so.
    @MainActor func testDenyTellsClaude() {
        let app = launch(claude: Self.fakeClaude)
        let panel = openPanelWithURL(app)

        ask("Please approve \(stamp)", in: app)
        waitForValue("Allow Write?", of: app.approval)
        app.denyButton.click()
        waitForValue("Answer 1: Denied: The owner declined.", of: app.answers.element(boundBy: 0))
        XCTAssertFalse(app.approval.exists)
        shot("denied", of: panel)
    }
}
