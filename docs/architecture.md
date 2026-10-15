# Architecture

```
 Hotkey (KeyboardShortcuts) ─┐
 aside:// URL ───────────────┼─▶ PanelController ─▶ FloatingPanel (NSPanel) ─▶ PanelView (SwiftUI)
 Menu bar item ──────────────┘          │
                              AssistantSession            (M1: state machine, owns interrupts)
                   ┌──────────────┼──────────────┐
              SpeechInput     ClaudeClient     SpeechOutput
              (M2)            (M1)             (M3)
```

Built so far: the panel, hotkey, menu bar item, URL scheme, `ClaudeLocator`, and logging. The rest is planned in the milestone shown.

## Panel

`FloatingPanel` (`App/Sources/PanelController.swift`) is a borderless `NSPanel` with `.nonactivatingPanel`: it takes keyboard input without activating Aside, so the app the user was in stays frontmost. `.canJoinAllSpaces` and `.fullScreenAuxiliary` put it on the current Space and over full-screen apps. Esc (`cancelOperation`) and losing key status (a click outside) hide it. The app is `LSUIElement`: no Dock icon, just a menu bar item.

## Claude

The app runs the Claude Code CLI as a child process. There is no API key, and Anthropic's SDKs aren't involved.

- **Finding it.** GUI apps don't get the shell's PATH. `ClaudeLocator` (`AsideCore`) checks a configured path, then the common install locations, then asks the login shell.
- **Process model (M1).** One long-lived process per conversation:
  `claude -p --input-format stream-json --output-format stream-json --verbose --include-partial-messages --model <model> --setting-sources project --strict-mcp-config`.
  Each user message is one JSON line on stdin. Text arrives as `stream_event` lines with `content_block_delta` / `text_delta`, and each turn ends with a `result` line. The process is started when the hotkey is pressed, so it is ready by the time the user has typed or spoken.
- **Isolation.** The process runs in `~/Library/Application Support/Aside/workspace/`. That folder's `CLAUDE.md` sets the assistant's voice (short, speakable answers), and its `.claude/settings.json` allows only the tools Aside needs. `--setting-sources project` keeps the owner's own Claude Code settings, hooks, and plugins out. `--strict-mcp-config` keeps their MCP servers out.
- **Permissions (M4).** With `--permission-prompts host`, tool permission requests come back to the app over the stream, so the panel can ask "Create this event?" instead of the request failing.
- **Calendar (M4).** First try the owner's claude.ai Google Calendar connector. `--strict-mcp-config` may hide connectors; check this before choosing an MCP config.

## Build and signing

- XcodeGen generates the project from `project.yml`.
- Builds are signed with the owner's Apple Development certificate (team `WHZ7FDCNMT`). Privacy grants follow the signature, so a stable identity means microphone and speech permissions survive rebuilds. There is no hardened runtime, no sandbox (a sandboxed app can't spawn `claude`), and no notarization.
- The bundle ID is `com.rigomart.aside`. Verification builds will get their own bundle ID (`.verify`) so they never collide with the owner's running copy.
