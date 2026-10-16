---
name: verify-aside
description: Prove a user-visible change in Aside, the macOS menu bar assistant (floating panel, global hotkey, menu bar item), by writing a throwaway XCUITest that drives the real app and running it with scripts/verify. Use whenever a change touches what the owner sees or does in the app, before calling it done. Unit tests and `make check` do not substitute for it.
---

# verify-aside

## What proof is

A change is proven by a short throwaway XCUITest that does what the owner does (press the hotkey, click the menu bar item, type into the panel) and asserts what they would see. You write it in `UITests/Scratch/`, run it against your own instance of the app, and put its title, pass line and screenshots in your report. The committed tests in `UITests/Tests/` are worked examples to copy from, not a suite to keep green. Looking at the app by hand helps you decide what to test; it never counts as proof.

```bash
scripts/verify up --name my-task              # build Aside Verify and the UI tests (15-60 s)
scripts/verify doctor --name my-task          # health check; every check should be ok
scripts/verify run MyChangeTests --name my-task   # rebuild what changed, run, export evidence
scripts/verify down --purge --name my-task    # stop leftovers, delete the build; evidence stays
```

Every command prints one JSON object. `scripts/verify --help` lists them all.

## Isolation

- Tests drive **Aside Verify**: the `Verify` build configuration in `project.yml`, bundle ID `com.rigomart.aside.verify`, URL scheme `aside-verify://`, hotkeys **Control-Option-Command-Space** (open) and **Control-Option-Shift-Command-Space** (talk). The owner's own Aside (`com.rigomart.aside`, `aside://`, Control-Option-Space and Control-Option-Shift-Space) is usually running; tests never touch it, and `down` never stops it. Don't use `aside://`, `make run` or `make stop` for verification.
- An instance is a named build under `.verify/<name>/` (`DerivedData/`, `results/`, `evidence/`, `logs/`, `instance.json`). Start your own per task with `--name <short-task-name>` and purge it when you're done; don't run in an instance someone else started (`default` included). Instances build in parallel.
- Each instance's build registers another Aside Verify with LaunchServices, which is one more reason to purge when done. The owner's `aside://` goes to their own copy only.
- **One run per Mac.** UI tests take the real pointer, keyboard and focus. `run` holds a lock (`$TMPDIR/aside-verify-ui.lock`) across every checkout and refuses while another run holds it. Wait and retry; never remove someone else's lock.
- An instance remembers its branch. After a branch switch, `run` and `doctor` refuse; recreate it with `scripts/verify down --purge --name <task> && scripts/verify up --name <task>`.

## Users and test data

Aside has no accounts. Its settings are the two hotkeys, the claude path (`claudePath`) and the audio file heard instead of the microphone (`audioInputFile`), in the `com.rigomart.aside.verify` defaults domain; `launch()` sets them with launch arguments every time. Its only files are claude's workspace, and `launch()` points `ASIDE_DATA_DIRECTORY` at `.verify/<name>/data/<stamp>/`, so tests never share the owner's data or each other's. Each `launch()` starts a fresh process with `-ApplePersistenceIgnoreState YES`. Use `stamp` (unique per test) in anything you type, so a value you assert can only have come from your test.

**Which claude.** `launch(claude: Self.fakeClaude)` points Aside at `UITests/Support/fake-claude`, which answers "Answer <n>: <question>" (n counts from 1 per process) and exits with status 3 and "something broke" on a question containing "boom". Use it to assert exact text, follow-ups, new conversations and failures. `launch(claude: "/nonexistent/claude")` arranges a missing claude. **What it hears.** `launch(claude: Self.fakeClaude, heard: Self.spokenQuestion)` makes the talk hotkey hear `UITests/Support/spoken-question.m4a` (`say` reading "What is the tallest mountain in Peru") instead of the microphone; Aside writes `Self.spokenQuestionText` in the field. Make another clip with `say -o <file>.m4a --file-format=m4af --data-format=aac "<words>"` (`"[[slnc 1500]]"` is silence). Without `heard:` the talk hotkey uses the microphone, and macOS asks the person at the Mac to allow it, which blocks the run: don't. `launch()` uses the owner's real claude: use it when the change is about what real answers look like or about the claude process itself. Real answers take 2–30 s and cost a little subscription usage; ask for something checkable (`"Reply with only the word \(stamp), nothing more."`) and assert with `CONTAINS`, because wording varies by design.

## Prove a change

1. Find the closest example in `UITests/Tests/` and the feature map in [features/README.md](features/README.md).
2. Write `UITests/Scratch/<Something>Tests.swift`: subclass `VerifyTestCase`, mark each test `@MainActor`, reach the panel through the entry point your change touched, assert exact values, and `shot(...)` the before and after.
3. `scripts/verify run <Class> --name <task>` or `<Class>/<testMethod>`. It regenerates the Xcode project, so a new scratch file is picked up with no other step. A compile error comes back as `"error":"Build failed."` with the errors listed.
4. On failure, read the failure message and line, then `failure-tree1.txt` in the evidence folder (what was on screen: roles, labels, identifiers, values), then `failure-display*.png` and the screen recording. Fix the test or the app, rerun.
5. Report (see Proof standards), with each scratch test's source in the report. Then delete your scratch files: every run in every instance compiles all of `UITests/Scratch/`, so a leftover that stops compiling breaks other agents' runs. If another agent's scratch file breaks your build, tell the owner rather than deleting it.
6. `scripts/verify down --purge --name <task>`. An empty `stopped` list is normal: each test's teardown already quits what it launched.

A complete scratch test that passes as written:

```swift
import XCTest

final class QuestionTypingTests: VerifyTestCase {
    /// Text typed into the open panel shows in its field.
    @MainActor func testTypedQuestionShowsInField() {
        let app = launch()
        let panel = openPanelWithURL(app)

        app.askField.typeText("What is \(stamp)?")

        XCTAssertEqual(app.askField.value as? String, "What is \(stamp)?")
        shot("typed-question", of: panel)
    }
}
```

`scripts/verify run QuestionTypingTests --name <task>` prints `{"ok":true,"passed":true,"tests":[{"test":"QuestionTypingTests/testTypedQuestionShowsInField()","result":"Passed",...}],"evidence":".../.verify/default/evidence/<time>","screenshotsAndRecordings":[".../typed-question.png"],...}`.

## Driving

Helpers live in `UITests/Support/`. Read both files before writing a test; copy their style.

| Need | Use |
| --- | --- |
| Launch Aside Verify | `launch()`, `launch(claude: Self.fakeClaude)` (see Which claude), or `launch(["-Arg", "value"])` to arrange a precondition through a user setting |
| The panel, its field, the claude line | `app.panel` (a dialog, identifier `panel`), `app.askField` (placeholder "Ask anything"), `app.claudeStatus` (identifier `claudeStatus`) |
| Ask, and read the transcript | `ask("What is \(stamp)?", in: app)` (types it and Return); `app.questions`, `app.answers`, `app.errors` (queries, oldest first: `.element(boundBy: 0)`); `app.activity` ("Thinking…", "Searching the web…"); `app.newConversationButton` |
| Wait for exact text | `waitForValue("Answer 1: What is \(stamp)?", of: app.answers.element(boundBy: 0))` |
| Open with the hotkey, another app in front | `let calculator = launchFrontApp()`, then `pressHotkey(over: calculator, in: app)` |
| Talk | `pressTalkHotkey(over: calculator, in: app)` opens the panel listening; in an open panel, `app.askField.typeKey(Self.talkHotkey.key, modifierFlags: Self.talkHotkey.modifiers)` starts listening or sends. Needs `launch(heard:)` |
| Listening status and voice errors | `app.voiceStatus` ("Starting the microphone…", "Listening… ⌃⌥⇧⌘Space sends, Esc cancels", "Sending…") and `app.voiceMessage` ("Didn't hear anything.", failures); both are static texts: read `.value` |
| Open from the menu bar | `openPanelFromMenuBar(app)`: status item `Aside`, menu item `Show Aside` |
| Open when how it opens is not the change | `openPanelWithURL(app)` (`aside-verify://show`) |
| Any URL: `show`, `hide`, `toggle` | `openURL("toggle")`, then `waitForPanel(in: app)` or `panel.waitForNonExistence(timeout: 5)` |
| Wait for an open panel with focus in its field | `waitForPanel(in: app)`, after any new way of opening it |
| Close | `app.askField.typeKey(.escape, modifierFlags: [])`, then `panel.waitForNonExistence(timeout: 5)` |
| Is the other app still in front? | `XCTAssertEqual(calculator.state, .runningForeground)`, `XCTAssertNotEqual(app.state, .runningForeground)` |
| Calculator's display | `display(of: calculator)` |
| Evidence | `shot("label", of: panel)` (cropped from its display); for a closed panel, keep `let frame = panel.frame` while it's open and later `shot("closed", region: frame)`; `shotScreens("label")` (every display, including whatever else the owner has open: use only when the change is about other apps); `tree(app)` |

- Query from a container by what the owner sees: `app.panel.textFields["Ask anything"]`, `app.statusItems["Aside"]`, `app.menuItems["Show Aside"]`. Add an `.accessibilityIdentifier` in the app for anything without a stable label, and add it to the table above.
- Wait on conditions: `waitForExistence(timeout:)`, `waitForNonExistence(timeout:)`, or `XCTNSPredicateExpectation` + `XCTWaiter.wait` for a value or `hasKeyboardFocus`. `sleep` is never proof.
- Assert exact text. Use `BEGINSWITH` only for text that varies by design, as `testPanelShowsWhereClaudeIs` does with the claude path.
- Never call `app.activate()` on Aside: the panel is non-activating by design, and activating changes the behavior under test. Never use `app.open(url)`: it quits and relaunches Aside without its launch arguments.
- To see what is on screen mid-test, call `tree(app)` and read the attachment in the evidence folder.
- Light appearance: `launch(["-NSRequiresAquaSystemAppearance", "YES"])`. This Mac runs in dark mode, which is the default look; `-AppleInterfaceStyle Light` does nothing.

## Proof standards

- Drive the real user path: the hotkey, the menu bar item, typing, Esc, clicks. Never call app internals, write defaults, or post notifications to produce the behavior under test. Arranging a precondition through something a user could also set (a launch-argument setting, the URL when the entry point isn't the change) is fine.
- Capture the action and the result: a `shot` before and after, not only the final state.
- Drive every entry point the change touched. The panel opens from the hotkey, the menu bar item and the URL; a change to opening or focus needs all three, or the report names the ones not driven. URL tests send the URL straight to the instance's app, so they prove how Aside handles it, not how LaunchServices routes it.
- A throwaway test isn't in the diff, so the report carries it: each test's title, the entry points and variants it drove, its `"result":"Passed"` line, and the paths of its screenshots.
- An entry point that can't be reached is reported with the step attempted and the unmet precondition, never as verified another way.
- A check that couldn't run (a skipped test, a run the lock refused, a permission prompt) is `INCONCLUSIVE`, never a pass.
- If the same step fails twice, stop that item, report it `INCONCLUSIVE` with the failing step and its output, and move on.
- When two ways of looking disagree, trust the test's exact assertion and find out why before writing a rule about the app. An XCUITest quirk is not app behavior.
- Behavior no test reaches (below) goes into `docs/manual-tests.md` and your report names the steps for the owner. Only that: a step a unit or UI test already proves stays out, even when the owner would see it on the way. The owner shouldn't redo what a test proved.

## What tests can't reach

| Path | Status |
| --- | --- |
| Another app in full screen, another Space, Mission Control, Stage Manager | No test reaches them. Manual tests 5 and 6 in `docs/manual-tests.md`. |
| Which display the panel opens on | It follows the pointer, which a person may be moving. Manual test 1. |
| Typing going back to the previous app after Esc | Works with a real keyboard (the owner checked), but XCUITest can't show it (see Gotchas). Manual test 3. |
| How fast an answer streams; copying answer text with the mouse | "Text loop (M1)" in `docs/manual-tests.md`. The 10-minute idle reset is unit-tested in `AssistantSessionTests`. |
| The microphone, the permission prompt, headsets, noise (M2) | Tests hear a file (`launch(heard:)`), so everything after the microphone is covered. The rest is "Voice input (M2)" in `docs/manual-tests.md`. |
| Sound (M3) | Prove what the panel shows (speaking indicator). The sound itself is checked by ear. |
| Light appearance on a light system, `-AppleInterfaceStyle Dark` | Not checked; this Mac runs dark. |

## Look around

To see the Verify build by hand: `scripts/verify up`, then
`open -n "$(scripts/verify env | jq -r .app)" --args -KeyboardShortcuts_togglePanel '"{\"carbonModifiers\":6400,\"carbonKeyCode\":49}"' -KeyboardShortcuts_talk '"{\"carbonModifiers\":6912,\"carbonKeyCode\":49}"'`
and press Control-Option-Command-Space. Quit it from its menu bar icon (the second speech bubble) or with `scripts/verify down`. Looking is not proof.

## Doctor and cleanup

- `scripts/verify doctor`: read-only. Checks Xcode, XcodeGen, automation mode, the signing identity, the instance's branch and build, and the screen lock. `ownersAside` shows whether the owner's copy is running; that is fine.
- `scripts/verify down [--dry-run]`: stops processes whose command line contains this instance's folder (its xcodebuild, test runner and Aside Verify). Never by name. Run it after a failed or interrupted run.
- `scripts/verify down --purge`: also deletes the build and `instance.json`.
- `results/` (`.xcresult` bundles), `evidence/<time>/<Class.test>/` and `logs/` survive both. Open a bundle in Xcode with `open <bundle>`, or read it with `xcrun xcresulttool get test-results tests --path <bundle>`.

## Gotchas

- **The hotkey step takes about 10 s.** XCUITest sends the key to the front app and waits up to 10 s for it to arrive; the hotkey takes it first, so the wait always runs out. That is expected, not a hang.
- **XCUITest keys after Esc don't reach the app in front.** After the panel closes, XCUITest's next `typeText` to Calculator never arrives (and costs a 10 s wait), though with a real keyboard typing goes straight back to the app the owner left. This is an XCUITest limitation, not app behavior: don't assert that typing returns to the previous app; manual test 3 covers it. (It was first reported to the owner as a likely app bug; their manual check disproved it.)
- **XCUITest can't type a lowercase "c" on this Mac.** `typeText("Please crash")` arrives as "Please rash", in TextEdit too, so it isn't Aside (checked 2026-10-15). Keep lowercase "c" out of typed text (`stamp` is uppercase, which works) and don't send it with `typeKey`. A real keyboard is unaffected.
- **Panel screenshots.** `panel.screenshot()` and other element screenshots fail with "Image creation failed". `shot` crops a display screenshot instead. `app.screenshot()` captures the main display, not the panel's.
- **Screen recordings** are attached only to failed tests, and cover only the main display. The panel opens on the display the pointer is on, which may be another one; `failure-display*.png` covers every display.
- **Calculator.** `launchFrontApp()` quits a running Calculator and relaunches it. A run killed partway can leave it open; quit it.
- **A person at the keyboard.** A click or keystroke during a run moves focus, the panel hides, and the test fails. Rerun once; if it fails again the same way, report `INCONCLUSIVE`. In the logs, every close writes "Hidden: lost focus" first (`orderOut` makes the panel resign key), followed by "Hidden" (URL, hotkey, menu) or "Hidden: Esc". A "lost focus" line with nothing after it is the one that means something else took focus.
- **Accessibility prompt.** XCUITest needs no Accessibility permission. If macOS asks to give `AsideUITests-Runner` (or anything else) Accessibility access, a test is posting raw `CGEvent`s; drive with XCUITest's `typeKey`/`typeText` instead and tell the owner to decline.
- **Automation mode** is set to run without a password on this Mac (`doctor` checks it). If that changes, the owner runs `sudo automationmodetool enable-automationmode-without-authentication` once.
- **Swift 6.** The UI test target is not `MainActor` by default (an `XCTestCase` subclass can't be); mark test methods and helpers `@MainActor`.
- **Logs** explain, never prove: `/usr/bin/log show --info --last 5m --style compact --predicate 'subsystem == "com.rigomart.aside"'` (the full path, because zsh has a `log` builtin). It shows both copies; tell them apart by the PID. "Shown", "Hidden", "Hidden: Esc" and "Hidden: lost focus" come from `PanelController`.
