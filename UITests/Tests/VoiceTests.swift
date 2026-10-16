import XCTest

/// Talking, with `spoken-question.m4a` standing in for the microphone and `fake-claude` answering.
final class VoiceTests: VerifyTestCase {
    /// The talk hotkey opens the panel listening over another app, what's heard shows in the field as it's
    /// said, and pressing the hotkey again sends it.
    @MainActor func testTalkHotkeyListensAndSecondPressSends() {
        let app = launch(claude: Self.fakeClaude, heard: Self.spokenQuestion)
        let calculator = launchFrontApp()
        let panel = pressTalkHotkey(over: calculator, in: app)

        XCTAssertTrue(app.voiceStatus.waitForExistence(timeout: 5), "No listening status")
        waitForValue(Self.spokenQuestionText, of: app.askField, timeout: 30)
        XCTAssertEqual(app.voiceStatus.value as? String, "Listening… ⌃⌥⇧⌘Space sends, Esc cancels")
        XCTAssertEqual(calculator.state, .runningForeground, "Calculator should stay the active app")
        shot("heard", of: panel)

        app.askField.typeKey(Self.talkHotkey.key, modifierFlags: Self.talkHotkey.modifiers)
        waitForValue("Answer 1: \(Self.spokenQuestionText)", of: app.answers.element(boundBy: 0))
        XCTAssertEqual(app.questions.element(boundBy: 0).value as? String, Self.spokenQuestionText)
        XCTAssertEqual(app.askField.value as? String, "", "Sending should clear the field")
        XCTAssertFalse(app.voiceStatus.exists, "Still listening after sending")
        XCTAssertEqual(calculator.state, .runningForeground, "Calculator should stay the active app")
        shot("sent", of: panel)
    }

    /// Talking adds to what was typed, and Esc puts the field back as it was.
    @MainActor func testEscThrowsAwayWhatWasHeard() {
        let app = launch(claude: Self.fakeClaude, heard: Self.spokenQuestion)
        let panel = openPanelWithURL(app)
        app.askField.typeText("Typed \(stamp)")

        app.askField.typeKey(Self.talkHotkey.key, modifierFlags: Self.talkHotkey.modifiers)
        waitForValue("Typed \(stamp) \(Self.spokenQuestionText)", of: app.askField, timeout: 30)
        shot("heard-after-typed", of: panel)

        app.askField.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(panel.waitForNonExistence(timeout: 5), "Esc did not close the panel")
        openURL("show")
        _ = waitForPanel(in: app)
        XCTAssertEqual(app.askField.value as? String, "Typed \(stamp)")
        XCTAssertFalse(app.voiceStatus.exists, "Still listening after Esc")
        XCTAssertEqual(app.answers.count, 0)
        shot("after-esc", of: panel)
    }

    /// Closing the panel with the open hotkey stops listening and keeps what was heard, unsent.
    @MainActor func testClosingKeepsWhatWasHeard() {
        let app = launch(claude: Self.fakeClaude, heard: Self.spokenQuestion)
        let panel = openPanelWithURL(app)

        app.askField.typeKey(Self.talkHotkey.key, modifierFlags: Self.talkHotkey.modifiers)
        waitForValue(Self.spokenQuestionText, of: app.askField, timeout: 30)
        app.askField.typeKey(Self.hotkey.key, modifierFlags: Self.hotkey.modifiers)
        XCTAssertTrue(panel.waitForNonExistence(timeout: 5), "The hotkey did not close the panel")

        openURL("show")
        _ = waitForPanel(in: app)
        XCTAssertEqual(app.askField.value as? String, Self.spokenQuestionText)
        XCTAssertFalse(app.voiceStatus.exists, "Still listening after closing")
        XCTAssertEqual(app.answers.count, 0, "Closing should not send")
        shot("reopened", of: panel)
    }

    /// Typing while listening stops listening and adds to what was heard; Return sends it all.
    @MainActor func testTypingStopsListening() {
        let app = launch(claude: Self.fakeClaude, heard: Self.spokenQuestion)
        let panel = openPanelWithURL(app)
        app.askField.typeKey(Self.talkHotkey.key, modifierFlags: Self.talkHotkey.modifiers)
        waitForValue(Self.spokenQuestionText, of: app.askField, timeout: 30)
        shot("listening", of: panel)

        app.askField.typeText(" \(stamp)")
        XCTAssertTrue(app.voiceStatus.waitForNonExistence(timeout: 5), "Still listening after typing")
        XCTAssertEqual(app.askField.value as? String, "\(Self.spokenQuestionText) \(stamp)")
        shot("typed", of: panel)

        app.askField.typeText("\n")
        waitForValue("Answer 1: \(Self.spokenQuestionText) \(stamp)", of: app.answers.element(boundBy: 0))
    }

    /// When listening fails, the panel says why. Here the audio file is missing; for the owner it would be
    /// the microphone.
    @MainActor func testListeningFailureShows() {
        let app = launch(claude: Self.fakeClaude, heard: "/nonexistent/heard.m4a")
        let panel = openPanelWithURL(app)
        app.askField.typeKey(Self.talkHotkey.key, modifierFlags: Self.talkHotkey.modifiers)
        XCTAssertTrue(app.voiceMessage.waitForExistence(timeout: 10), "No failure message")
        let message = app.voiceMessage.value as? String ?? ""
        XCTAssertTrue(message.hasPrefix("Couldn't read the audio file /nonexistent/heard.m4a"), "Saw \(message)")
        shot("failed", of: panel)
    }
}
