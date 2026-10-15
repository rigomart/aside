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
