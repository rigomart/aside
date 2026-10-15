import XCTest

final class PanelTests: VerifyTestCase {
    /// The hotkey opens the panel over the app the user is in, typing goes into the panel,
    /// that app stays in front, and Esc closes the panel.
    @MainActor func testHotkeyOpensPanelOverFrontApp() {
        let app = launch()
        let calculator = launchFrontApp()
        calculator.typeText("12")
        XCTAssertEqual(display(of: calculator), "12")

        let panel = pressHotkey(over: calculator, in: app)
        shot("panel-open", of: panel)
        XCTAssertEqual(calculator.state, .runningForeground, "Calculator should stay the active app")
        XCTAssertNotEqual(app.state, .runningForeground, "Aside should not become the active app")

        app.askField.typeText("34")
        XCTAssertEqual(app.askField.value as? String, "34")
        XCTAssertEqual(display(of: calculator), "12", "Typing went to Calculator instead of the panel")
        shot("panel-typed", of: panel)

        app.askField.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(panel.waitForNonExistence(timeout: 5), "Esc did not close the panel")
    }

    /// The menu bar item's Show Aside opens the panel, and pressing the hotkey while it is open closes it.
    @MainActor func testMenuBarOpensPanelAndHotkeyClosesIt() {
        let app = launch()
        let panel = openPanelFromMenuBar(app)
        shot("panel-from-menu", of: panel)

        app.askField.typeKey(Self.hotkey.key, modifierFlags: Self.hotkey.modifiers)
        XCTAssertTrue(panel.waitForNonExistence(timeout: 5), "The hotkey did not close the open panel")
    }

    /// The line under the field says where `claude` was found.
    @MainActor func testPanelShowsWhereClaudeIs() {
        let app = launch()
        let panel = openPanelWithURL(app)

        let found = NSPredicate(format: "value BEGINSWITH %@", "claude: /")
        let status = XCTNSPredicateExpectation(predicate: found, object: app.claudeStatus)
        XCTAssertEqual(XCTWaiter.wait(for: [status], timeout: 10), .completed,
                       "Status line says: \(app.claudeStatus.value as? String ?? "nothing")")
        shot("claude-status", of: panel)
    }
}
