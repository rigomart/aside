import AppKit
import XCTest

/// Dictation into TextEdit, with `spoken-question.m4a` standing in for the microphone. Pasting needs Aside Verify
/// allowed in System Settings › Privacy & Security › Accessibility (it shows there as "Aside").
final class DictationTests: VerifyTestCase {
    /// The dictation hotkey shows the pill over another app, which stays in front; pressing it again pastes
    /// what was heard at the cursor and puts the clipboard back.
    @MainActor func testSecondPressPastesAtTheCursorAndKeepsTheClipboard() {
        let app = launch(claude: Self.fakeClaude, heard: Self.spokenQuestion)
        let textEdit = launchTextEdit()
        textEdit.textViews.firstMatch.typeText("Note \(stamp): ")
        setClipboard("Clipboard \(stamp)")

        startDictating(over: textEdit, in: app)
        XCTAssertEqual(textEdit.state, .runningForeground, "TextEdit should stay the active app")
        shot("listening", of: app.dictationPill)
        let frame = app.dictationPill.frame

        pressDictateHotkey(over: textEdit)
        waitForText("Note \(stamp): \(Self.spokenQuestionText)", in: textEdit)
        XCTAssertTrue(app.dictationPill.waitForNonExistence(timeout: 5), "The pill stayed after pasting")
        waitForClipboard("Clipboard \(stamp)")
        XCTAssertEqual(textEdit.state, .runningForeground, "TextEdit should stay the active app")
        shot("pasted", region: textEdit.windows.firstMatch.frame)
        shot("pill-gone", region: frame)
    }

    /// Return pastes too, and isn't typed into the app.
    @MainActor func testReturnPastes() {
        let app = launch(claude: Self.fakeClaude, heard: Self.spokenQuestion)
        let textEdit = launchTextEdit()
        setClipboard("Clipboard \(stamp)")

        startDictating(over: textEdit, in: app)
        textEdit.typeKey(.return, modifierFlags: [])
        waitForText(Self.spokenQuestionText, in: textEdit)
        XCTAssertTrue(app.dictationPill.waitForNonExistence(timeout: 5), "The pill stayed after pasting")
        waitForClipboard("Clipboard \(stamp)")
    }

    /// Esc throws away what was heard: nothing is pasted, and the clipboard is untouched.
    @MainActor func testEscPastesNothing() {
        let app = launch(claude: Self.fakeClaude, heard: Self.spokenQuestion)
        let textEdit = launchTextEdit()
        textEdit.textViews.firstMatch.typeText("Note \(stamp)")
        setClipboard("Clipboard \(stamp)")

        startDictating(over: textEdit, in: app)
        shot("listening", of: app.dictationPill)
        let frame = app.dictationPill.frame
        textEdit.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(app.dictationPill.waitForNonExistence(timeout: 5), "Esc did not hide the pill")
        // A paste would have landed by now; the restore after one takes half a second.
        sleep(2)
        XCTAssertEqual(text(of: textEdit), "Note \(stamp)")
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "Clipboard \(stamp)")
        shot("after-esc", region: frame)
    }

    /// Hearing nothing pastes nothing, and the pill says so for a moment.
    @MainActor func testHearingNothingSaysSo() {
        // Each hotkey press takes XCUITest about 10 s, longer than the message's 2 s.
        let app = launch(claude: Self.fakeClaude, heard: Self.silence, ["-dictationMessageSeconds", "15"])
        let textEdit = launchTextEdit()

        startDictating(over: textEdit, in: app)
        pressDictateHotkey(over: textEdit)
        XCTAssertTrue(app.dictationMessage.waitForExistence(timeout: 10), "No message")
        XCTAssertEqual(app.dictationMessage.value as? String, "Didn't hear anything")
        shot("heard-nothing", of: app.dictationPill)
        XCTAssertTrue(app.dictationPill.waitForNonExistence(timeout: 20), "The message stayed")
        XCTAssertEqual(text(of: textEdit), "")
    }

    /// The dictation hotkey closes the open panel and dictates instead; nothing goes to Claude.
    @MainActor func testDictatingClosesThePanel() {
        let app = launch(claude: Self.fakeClaude, heard: Self.spokenQuestion)
        let panel = openPanelWithURL(app)

        app.askField.typeKey(Self.dictateHotkey.key, modifierFlags: Self.dictateHotkey.modifiers)
        XCTAssertTrue(panel.waitForNonExistence(timeout: 5), "The panel stayed open")
        XCTAssertTrue(app.dictationStatus.waitForExistence(timeout: 10), "No dictation pill")
        shot("dictating", of: app.dictationPill)

        openURL("show")
        _ = waitForPanel(in: app)
        XCTAssertTrue(app.dictationPill.waitForNonExistence(timeout: 5), "Opening the panel should stop dictating")
        XCTAssertEqual(app.askField.value as? String, "")
        XCTAssertEqual(app.answers.count, 0)
    }

    /// Presses the dictation hotkey over `frontApp`, waits until it listens, and lets the clip play.
    @MainActor private func startDictating(over frontApp: XCUIApplication, in app: XCUIApplication) {
        pressDictateHotkey(over: frontApp)
        XCTAssertTrue(app.dictationStatus.waitForExistence(timeout: 10), "No dictation pill")
        let listening = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "Listening · Return pastes · Esc cancels"), object: app.dictationStatus
        )
        XCTAssertEqual(XCTWaiter.wait(for: [listening], timeout: 10), .completed, "Saw \(app.dictationStatus.label)")
        // The clips take about 2 s to play; the pill doesn't show the words, so there is nothing to wait on.
        sleep(3)
    }

    @MainActor private func setClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @MainActor private func waitForText(_ expected: String, in textEdit: XCUIApplication) {
        let shows = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", expected), object: textEdit.textViews.firstMatch)
        XCTAssertEqual(XCTWaiter.wait(for: [shows], timeout: 15), .completed, "TextEdit shows \"\(text(of: textEdit))\"")
    }

    @MainActor private func waitForClipboard(_ expected: String) {
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            NSPasteboard.general.string(forType: .string) == expected
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 5), .completed,
                       "The clipboard holds \"\(NSPasteboard.general.string(forType: .string) ?? "nothing")\"")
    }
}
