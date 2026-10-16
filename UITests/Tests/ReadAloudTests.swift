import XCTest

/// Reading answers aloud, with `spoken-question.m4a` standing in for the microphone and `fake-claude`
/// answering. Tests see the "Reading" chips under the answer; the sound itself plays on the Mac's speakers.
final class ReadAloudTests: VerifyTestCase {
    /// The answer to a spoken question is read aloud, and the chips go away once it has been said.
    @MainActor func testSpokenQuestionIsReadAloud() {
        let app = launch(claude: Self.fakeClaude, heard: Self.spokenQuestion)
        let calculator = launchFrontApp()
        let panel = pressTalkHotkey(over: calculator, in: app)
        waitForValue(Self.spokenQuestionText, of: app.askField, timeout: 30)

        app.askField.typeKey(Self.talkHotkey.key, modifierFlags: Self.talkHotkey.modifiers)
        waitForValue("Answer 1: \(Self.spokenQuestionText)", of: app.answers.element(boundBy: 0))
        XCTAssertTrue(app.readingStatus.waitForExistence(timeout: 5), "Not reading aloud")
        XCTAssertEqual(app.readingStatus.label, "Reading aloud. Esc stops.")
        shot("reading", of: panel)

        XCTAssertTrue(app.readingStatus.waitForNonExistence(timeout: 20), "Still reading after 20 s")
        XCTAssertEqual(app.answers.element(boundBy: 0).value as? String, "Answer 1: \(Self.spokenQuestionText)")
        shot("read", of: panel)
    }

    /// The answer to a typed question is not read aloud.
    @MainActor func testTypedQuestionIsNotReadAloud() {
        let app = launch(claude: Self.fakeClaude)
        let panel = openPanelWithURL(app)

        ask("What is \(stamp)?", in: app)
        waitForValue("Answer 1: What is \(stamp)?", of: app.answers.element(boundBy: 0))
        XCTAssertFalse(app.readingStatus.waitForExistence(timeout: 2), "A typed question's answer is being read")
        shot("answered", of: panel)
    }

    /// Esc stops reading mid-answer; closing the panel with the hotkey keeps reading. The question asks for
    /// a story, which takes `fake-claude` about 20 seconds to read.
    @MainActor func testEscStopsReadingAndClosingDoesNot() {
        let app = launch(claude: Self.fakeClaude, heard: Self.spokenQuestion)
        let panel = openPanelWithURL(app)
        askAloud("Tell a story \(stamp)", in: app)
        XCTAssertTrue(app.readingStatus.waitForExistence(timeout: 5), "Not reading aloud")

        app.askField.typeKey(Self.hotkey.key, modifierFlags: Self.hotkey.modifiers)
        XCTAssertTrue(panel.waitForNonExistence(timeout: 5), "The hotkey did not close the panel")
        openURL("show")
        _ = waitForPanel(in: app)
        XCTAssertTrue(app.readingStatus.exists, "Closing with the hotkey stopped reading")
        shot("still-reading", of: panel)

        app.askField.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(panel.waitForNonExistence(timeout: 5), "Esc did not close the panel")
        openURL("show")
        _ = waitForPanel(in: app)
        XCTAssertFalse(app.readingStatus.exists, "Still reading after Esc")
        XCTAssertTrue(app.answers.element(boundBy: 0).exists, "The answer should stay in the panel")
        shot("stopped", of: panel)
    }

    /// Talking while an answer is read stops reading, so the microphone doesn't hear it.
    @MainActor func testTalkingStopsReading() {
        let app = launch(claude: Self.fakeClaude, heard: Self.spokenQuestion)
        let panel = openPanelWithURL(app)
        askAloud("Tell a story \(stamp)", in: app)
        XCTAssertTrue(app.readingStatus.waitForExistence(timeout: 5), "Not reading aloud")

        app.askField.typeKey(Self.talkHotkey.key, modifierFlags: Self.talkHotkey.modifiers)
        XCTAssertTrue(app.voiceStatus.waitForExistence(timeout: 5), "Not listening")
        XCTAssertFalse(app.readingStatus.exists, "Still reading while listening")
        shot("listening", of: panel)
    }

    /// Types `typed`, then talks, so the question is `typed` plus the spoken clip, sent by voice.
    @MainActor private func askAloud(_ typed: String, in app: XCUIApplication) {
        app.askField.typeText(typed)
        app.askField.typeKey(Self.talkHotkey.key, modifierFlags: Self.talkHotkey.modifiers)
        waitForValue("\(typed) \(Self.spokenQuestionText)", of: app.askField, timeout: 30)
        app.askField.typeKey(Self.talkHotkey.key, modifierFlags: Self.talkHotkey.modifiers)
        XCTAssertTrue(app.answers.element(boundBy: 0).waitForExistence(timeout: 10), "No answer")
    }
}
