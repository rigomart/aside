# Architecture

```
 Hotkey (KeyboardShortcuts) ─┐
 aside:// URL ───────────────┼─▶ PanelController ─▶ FloatingPanel (NSPanel) ─▶ PanelView (SwiftUI)
 Menu bar item ──────────────┘          │
                              AssistantSession  ─▶ Conversation (what the panel shows)
                   ┌──────────────┼──────────────┐
              SpeechInput     ClaudeProcess    SpeechOutput
              (M2)                             (M3)
```

Built so far: the panel, hotkey, menu bar item, URL scheme, and the text loop (`AssistantSession`, `ClaudeProcess`, `Conversation`, `ClaudeEvent`, `Workspace`, `ClaudeLocator`, all in `AsideCore`). Speech is planned in the milestone shown.

## Conversation

`AssistantSession` (`AsideCore`) owns the conversation and its claude process. `PanelController.show()` calls `prepare()`, which starts claude if it isn't running, after first ending the conversation if it sat idle more than 10 minutes. Return in the field calls `send`; Command-N or the New conversation button calls `startNewConversation`, which stops the process and starts a fresh one. A question sent while an answer is still coming is ignored, and the field keeps its text.

`Conversation` is a plain value: each question with its streamed answer, an activity line ("Thinking…", "Searching the web…"), and an error. If claude exits for any reason the panel shows "claude stopped (exit status N): <last stderr line>", and the next question starts a new process with no memory of the old one. A failed turn (`result` with `is_error`) shows its message on that question.

Answers render inline Markdown (bold, italics, code, links). The transcript grows the panel downward up to 420 points, then scrolls and follows the newest text. The panel has a hidden Edit menu so Command-X, C, V, A and Z work in it.

## Panel

`FloatingPanel` (`App/Sources/PanelController.swift`) is a borderless `NSPanel` with `.nonactivatingPanel`: it takes keyboard input without activating Aside, so the app the user was in stays frontmost. `.canJoinAllSpaces` and `.fullScreenAuxiliary` put it on the current Space and over full-screen apps. Esc (`cancelOperation`) and losing key status (a click outside) hide it. The app is `LSUIElement`: no Dock icon, just a menu bar item.

## Claude

The app runs the Claude Code CLI as a child process. There is no API key, and Anthropic's SDKs aren't involved.

- **Finding it.** GUI apps don't get the shell's PATH. `ClaudeLocator` (`AsideCore`) checks a configured path, then the common install locations, then asks the login shell.
- **Process model (M1).** One long-lived process per conversation:
  `claude -p --input-format stream-json --output-format stream-json --verbose --include-partial-messages --model sonnet --setting-sources project --strict-mcp-config --tools WebSearch,WebFetch --allowedTools WebSearch,WebFetch --permission-prompts none`.
  Each user message is one JSON line on stdin. Text arrives as `stream_event` lines with `content_block_delta` / `text_delta`, a `content_block_start` marks each new text block or tool use, and each turn ends with a `result` line. The process is started when the panel opens, so it is ready by the time the user has typed or spoken. When Aside quits, claude sees its stdin close and exits.
- **Reading output.** `ClaudeProcess` reads pipes with `readabilityHandler`, because `FileHandle.bytes` holds a pipe's output back until its buffer fills, and splits lines on `\n` only. It ignores `SIGPIPE`, so writing to a claude that just died throws instead of killing Aside.
- **Isolation.** The process runs in `<data>/workspace/`, where `<data>` is `~/Library/Application Support/Aside` (or `ASIDE_DATA_DIRECTORY` from the launch environment, which UI tests set). Aside rewrites the folder's `CLAUDE.md` each time claude starts; it sets the assistant's voice (short, speakable answers). `--setting-sources project` keeps the owner's own Claude Code settings, hooks, plugins and `~/.claude/CLAUDE.md` out (checked on 2026-10-15). `--strict-mcp-config` keeps their MCP servers out. `--tools WebSearch,WebFetch` makes those the only tools, `--allowedTools` approves them, and `--permission-prompts none` denies anything else that would ask.
- **Configured path.** The `claudePath` user default, if set, is used instead of searching (`defaults write com.rigomart.aside claudePath /path/to/claude`). UI tests set it with a launch argument to point at `UITests/Support/fake-claude`.
- **Permissions (M4).** With `--permission-prompts host` instead of `none`, tool permission requests come back to the app over the stream, so the panel can ask "Create this event?" instead of the request failing.
- **Calendar (M4).** First try the owner's claude.ai Google Calendar connector. `--strict-mcp-config` may hide connectors; check this before choosing an MCP config.

## Build and signing

- XcodeGen generates the project from `project.yml`.
- Builds are signed with the owner's Apple Development certificate (team `WHZ7FDCNMT`). Privacy grants follow the signature, so a stable identity means microphone and speech permissions survive rebuilds. There is no hardened runtime, no sandbox (a sandboxed app can't spawn `claude`), and no notarization.
- The bundle ID is `com.rigomart.aside`.
- The `Verify` build configuration builds Aside Verify for UI tests: bundle ID `com.rigomart.aside.verify`, URL scheme `aside-verify://`. It runs beside the owner's copy without sharing defaults, privacy grants or `aside://`. UI tests give it the hotkey Control-Option-Shift-Space through a launch argument, because Carbon hotkeys aren't exclusive and a shared one would open both panels.
- `AsideUITests` (sources in `UITests/`) has its own scheme with the `Verify` configuration, so `make check` never runs it. `scripts/verify` builds and runs it into `.verify/<instance>/`.
