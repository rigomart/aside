# Decisions

Newest last. Each entry: what was decided, why, and what would change it.

## 1. Native Swift app, AppKit panel with SwiftUI views
Floating, non-activating overlays that work over full-screen apps are where Electron and Tauri struggle. Only macOS matters.

## 2. Claude Code CLI as the backend
It runs on the owner's subscription with no API key and can reuse Claude Code's tools and MCP. There is no Swift SDK, and a Node or Python sidecar for the Agent SDK would add a runtime for no gain. Revisit if the CLI's stream-json protocol stops being stable enough.

## 3. A long-lived stream-json process from milestone 1, started on hotkey press
Measured on 2026-10-14 (Claude Code 2.1.300, no tools, MCP off, one-sentence answer), first token after sending:

| | Haiku | Sonnet |
| --- | --- | --- |
| Process started on send (cold) | 1.6–1.9 s | not measured |
| Process started 2.5 s earlier (prewarmed) | 0.9–1.4 s | 1.4 s (one run) |

Starting the process early saved 0.5–0.9 s in back-to-back runs. A one-shot process per question would have to be rewritten later anyway, so it isn't worth building. Enabling WebSearch/WebFetch didn't measurably add latency.

## 4. macOS 26 only; no sandbox, no notarization
Personal app on the owner's Mac (macOS 26.6). This allows `SpeechAnalyzer` and current SwiftUI. The sandbox would block spawning `claude`. Builds use the owner's Apple Development certificate so privacy grants persist.

## 5. XcodeGen; the generated project is not committed
Agents edit `project.yml` instead of `.pbxproj`, which they handle poorly. Packages are pinned with `exactVersion`, because the generated project's `Package.resolved` isn't committed.

## 6. Core logic in a local Swift package
`AsideCore` has no AppKit, so `swift test` runs in seconds without launching the app. The app target stays thin glue that is hard to unit test.

## 7. KeyboardShortcuts 3.1.0 for the hotkey; default Control-Option-Space
It provides the recorder UI for settings later. It uses the Carbon hotkey API, so it needs no Accessibility permission. The default avoids Spotlight (Cmd-Space), Finder search (Option-Cmd-Space), and ChatGPT (Option-Space).

## 8. Built fresh; Atticus is a reference only
About 2–3k lines designed from this brief are easier for agents to own than inherited code nobody has reviewed. Read Atticus for panel, hotkey, and speech details, and check its license before copying code.

## 9. A Stop hook runs `make check`
The owner doesn't review code, so an agent can't end a turn with a broken build or failing tests. `scripts/stop-check.sh` skips the check when sources haven't changed since the last pass.

## 10. Changes are proven with throwaway XCUITests against a separate Verify build
An agent proves a user-visible change by writing a short UI test that drives the real app (hotkey, menu bar, typing) and running it with `scripts/verify` (`.claude/skills/verify-aside`). XCUITest ships with Xcode, so nothing is added. The Verify build has its own bundle ID, URL scheme and hotkey, so it runs while the owner's copy is open. UI tests take over the screen and need about 30 s for the current examples, so they are not in `make check` or CI; adding them is the owner's call.

## 11. GitHub Actions runs `make check` on pushes to main and on pull requests
`.github/workflows/ci.yml` runs on the `macos-26` image, whose default Xcode (26.x) is the oldest the README supports, so CI catches anything that only builds on the owner's newer Xcode. The runner has no signing certificate, so CI builds unsigned via `XCODEBUILD_FLAGS=CODE_SIGNING_ALLOWED=NO`. The repo is public, so macOS minutes are free; if it goes private they bill at 10x, and CI would be worth trimming or dropping.

## 12. Sonnet answers
The owner chose quality over speed on 2026-10-15; measured first-token latency is about the same as Haiku (decision 3). It's `model` in `AssistantSession`.

## 13. A new conversation after 10 minutes idle, or on Command-N
Chosen by the owner on 2026-10-15. Idle means no question or finished answer for 10 minutes; the check runs when the panel opens, so an open panel is never cleared under the owner. The New conversation button (Command-N) shows once there is a transcript.

## 14. Web search and web fetch are claude's only tools, set on the command line
Quick lookups need the web, and nothing else is needed until calendar and notes (M4). `--tools`, `--allowedTools` and `--permission-prompts none` say this in one place, so the workspace holds only `CLAUDE.md` and no `.claude/settings.json`. Aside rewrites `CLAUDE.md` on every start so it always matches the app; to change the assistant's voice, change `Workspace.instructions`.

## 15. If claude exits, the next question starts a new conversation
The panel says so, and the next question starts a fresh process. Resuming with `--resume <session id>` would keep the context but adds code for something that hasn't happened outside tests. Revisit if the owner sees "claude stopped" in daily use.
