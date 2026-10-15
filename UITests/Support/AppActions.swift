import AppKit
import XCTest

extension XCUIApplication {
    /// Aside's floating panel. It is a borderless `NSPanel`, which XCUITest lists as a dialog.
    var panel: XCUIElement { dialogs["panel"] }

    /// The panel's text field, found by its placeholder.
    var askField: XCUIElement { panel.textFields["Ask anything"] }

    /// The line under the field that says where `claude` is, or that it is missing.
    var claudeStatus: XCUIElement { panel.staticTexts["claudeStatus"] }

    /// The transcript's questions, answers and errors, oldest first.
    var questions: XCUIElementQuery { panel.staticTexts.matching(identifier: "question") }
    var answers: XCUIElementQuery { panel.staticTexts.matching(identifier: "answer") }
    var errors: XCUIElementQuery { panel.descendants(matching: .any).matching(identifier: "error") }

    /// "Thinking…" or what Claude is doing, while an answer is still coming.
    var activity: XCUIElement { panel.staticTexts["activity"] }

    /// The button that starts a new conversation (Command-N). Shown once there is a transcript.
    var newConversationButton: XCUIElement { panel.buttons["New conversation ⌘N"] }
}

extension VerifyTestCase {
    /// Launches Calculator to stand in for the app the user is working in, and clears its display.
    /// `launch()` quits a Calculator that is already running; it keeps nothing worth losing.
    @MainActor func launchFrontApp() -> XCUIApplication {
        let calculator = XCUIApplication(bundleIdentifier: "com.apple.calculator")
        calculator.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        calculator.launch()
        addTeardownBlock { @MainActor in calculator.terminate() }
        calculator.typeKey(.escape, modifierFlags: [])
        return calculator
    }

    /// What Calculator's display shows, without the invisible direction mark it puts in front.
    @MainActor func display(of calculator: XCUIApplication) -> String {
        let value = calculator.scrollViews["StandardInputView"].staticTexts.firstMatch.value as? String ?? ""
        return value.trimmingCharacters(in: CharacterSet(charactersIn: "\u{200E}\u{200F}"))
    }

    /// Presses the verification hotkey with `frontApp` in front, as the user does, and returns the panel
    /// once its field has keyboard focus. XCUITest waits up to 10 s for `frontApp` to receive the key,
    /// which it never does because the hotkey takes it, so this step takes about 10 s.
    @MainActor func pressHotkey(over frontApp: XCUIApplication, in app: XCUIApplication) -> XCUIElement {
        frontApp.typeKey(Self.hotkey.key, modifierFlags: Self.hotkey.modifiers)
        return waitForPanel(in: app)
    }

    /// Clicks Aside's menu bar icon and chooses Show Aside. Returns the panel once its field has focus.
    @MainActor func openPanelFromMenuBar(_ app: XCUIApplication) -> XCUIElement {
        app.statusItems["Aside"].click()
        app.menuItems["Show Aside"].click()
        return waitForPanel(in: app)
    }

    /// Opens `aside-verify://show` in the running Verify build. Use it to arrange an open panel when
    /// the change is not about how the panel opens.
    @MainActor func openPanelWithURL(_ app: XCUIApplication) -> XCUIElement {
        openURL("show")
        return waitForPanel(in: app)
    }

    /// Opens `aside-verify://<action>` (`show`, `hide`, `toggle`) in this instance's Verify build.
    /// It goes to the app by path, so it proves how the app handles the URL, not how LaunchServices
    /// routes `aside://` links. `XCUIApplication.open(_:)` is not a substitute: it quits and relaunches
    /// the app without its launch arguments.
    @MainActor func openURL(_ action: String) {
        // The test runner sits next to the app it tests in Build/Products/Verify.
        let appURL = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("Aside.app")
        let opened = expectation(description: "open aside-verify://\(action)")
        NSWorkspace.shared.open(
            [URL(string: "aside-verify://\(action)")!], withApplicationAt: appURL,
            configuration: NSWorkspace.OpenConfiguration()
        ) { _, error in
            XCTAssertNil(error)
            opened.fulfill()
        }
        wait(for: [opened], timeout: 10)
    }

    /// Types `question` into the open panel and presses Return.
    @MainActor func ask(_ question: String, in app: XCUIApplication) {
        app.askField.typeText(question + "\n")
    }

    /// Waits until `element`'s value is `expected`, and fails with what it showed instead.
    @MainActor func waitForValue(_ expected: String, of element: XCUIElement, timeout: TimeInterval = 10,
                                 file: StaticString = #filePath, line: UInt = #line) {
        let shows = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", expected), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [shows], timeout: timeout), .completed,
                       "Expected \"\(expected)\", saw \"\(element.value as? String ?? "nothing")\"", file: file, line: line)
    }

    /// Waits for the panel to open with keyboard focus in its field, and returns it.
    @MainActor func waitForPanel(in app: XCUIApplication) -> XCUIElement {
        XCTAssertTrue(app.askField.waitForExistence(timeout: 5), "The panel did not open")
        let focused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasKeyboardFocus == true"), object: app.askField)
        XCTAssertEqual(XCTWaiter.wait(for: [focused], timeout: 5), .completed, "The panel's field did not get keyboard focus")
        return app.panel
    }
}
