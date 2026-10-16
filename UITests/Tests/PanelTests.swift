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

    /// The panel opens in the bottom-right corner of the screen the pointer is on, with no claude line
    /// when claude was found. An answer grows up from the field, which stays in the corner.
    @MainActor func testPanelOpensInTheBottomRightCorner() throws {
        let app = launch(claude: Self.fakeClaude)
        let panel = openPanelWithURL(app)

        // XCUITest frames are in points from the top left of the main display; AppKit's from the bottom left.
        let pointer = NSEvent.mouseLocation
        let screen = try XCTUnwrap(NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) })
        let mainHeight = try XCTUnwrap(NSScreen.screens.first).frame.height
        // The test runner's `visibleFrame` leaves the menu bar and Dock in, so the app's bottom edge, which
        // leaves the Dock out, can be up to a Dock's height higher.
        let visible = screen.visibleFrame
        let screenBottom = mainHeight - visible.minY
        XCTAssertEqual(panel.frame.maxX, visible.maxX, accuracy: 1, "The panel should touch the right edge")
        XCTAssertLessThanOrEqual(panel.frame.maxY, screenBottom + 1, "The panel runs off the bottom of the screen")
        XCTAssertGreaterThan(panel.frame.maxY, screenBottom - 150, "The panel should be at the bottom of the screen")
        XCTAssertFalse(app.claudeStatus.waitForExistence(timeout: 2), "A claude line shows though claude was found")
        shot("panel-right", of: panel)

        let field = app.askField.frame
        ask("Where \(stamp)?", in: app)
        waitForValue("Answer 1: Where \(stamp)?", of: app.answers.element(boundBy: 0))
        XCTAssertEqual(app.askField.frame, field, "The field moved when the answer came")
        XCTAssertLessThan(app.answers.element(boundBy: 0).frame.maxY, field.minY, "The answer should be above the field")
        shot("answer-above", of: panel)
    }
}
