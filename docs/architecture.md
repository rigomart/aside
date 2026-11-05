# Architecture

```
 Hotkeys (KeyboardShortcuts) ─┐
 aside:// URL ────────────────┼─▶ PanelController ─▶ FloatingPanel (NSPanel) ─▶ PanelView (SwiftUI)
 Menu bar item ───────────────┘          │
                       Composer (the field) ──▶ AssistantSession ─▶ Conversation (what the panel shows)
                              │                        │
                       SpeechListener            ClaudeProcess, Narrator ─▶ SpeechSpeaker
```

Built so far: the panel, hotkeys, menu bar item, URL scheme, the text loop (`AssistantSession`, `ClaudeProcess`, `Conversation`, `ClaudeEvent`, `Workspace`, `ClaudeLocator`), tools and approvals (`Tool`, `ApprovalRequest`), memory (`Memory`), voice input (`Composer`, `SpeechListener`), voice output (`Narrator`, `SpokenText`, `SpeechSpeaker`) and answer formatting (`AnswerBlock`), all but the panel in `AsideCore`.

## Conversation

`AssistantSession` (`AsideCore`) owns the conversation and its claude process. `PanelController.show()` calls `prepare()`, which starts claude if it isn't running. Return in the field calls `send`; Command-N or the New button calls `startNewConversation`, which stops the process, forgets the saved session and starts a fresh one. A question sent while an answer is still coming is ignored, and the field keeps its text.

The conversation lasts until New (decision 25). Each turn's `system`/`init` line names claude's session; `AssistantSession` keeps it as `sessionID` and saves it in `<data>/session-id`, and every claude it starts gets `--resume <id>`. All of them, the compacting copy too, start in `AssistantSession.launch`, so they share `ClaudeProcess.arguments`. Before the first question after a relaunch, the panel shows "Continuing your conversation" with the New chip. A resumed claude that exits before any turn begins means the session couldn't be resumed: the panel says "Couldn't continue the conversation (exit status N): <last stderr line>", and the saved ID is forgotten. Any other exit shows "claude stopped (exit status N): <last stderr line>", and the next question resumes the session.

Compaction happens in the background. Each reply's `message_start` reports its input, cache-read and cache-creation tokens (`.contextUsed`), which add up to the conversation's size. When a turn ends at 80,000 tokens or more (`compactAt`), `compactIfNeeded` starts a copy with `--resume <id> --fork-session` and sends it `/compact`. Its output goes to `compacting(_:)`, not the panel. When it reports `compact_boundary` (`.compacted`) and then its `result`, it becomes the live process, the old one stops, and its session ID is saved. `send` and `startNewConversation` stop a running copy, and so does the live process exiting. Claude Code's own autocompact (`--autocompact 150000`) is the backstop; if it runs, its `status: compacting` line (`.compacting`) shows "Condensing the conversation…" in the answer card.

`Conversation` is a plain value: each question with its streamed answer, an activity line ("Thinking…", "Searching the web…"), what claude saved to memory meanwhile (see Memory), and an error. A failed turn (`result` with `is_error`) shows its message on that question.

The panel shows only the newest question and its answer; earlier ones stay in claude's context (decision 21). `AnswerBlock` (`AsideCore`) splits the answer's Markdown into paragraphs, headings, list items and code (tables count as code), and `PanelView` joins them into one `AttributedString` with inline Markdown (bold, italics, code, links), so the answer selects as one text. The answer grows the card upward up to 300 points, then scrolls and follows the newest text. The panel has a hidden Edit menu so Command-X, C, V, A and Z work in it.

## Voice input

`Composer` (`AsideCore`) owns the field's text and sends it: Return and the talk hotkey both go through it, and the field writes edits back through `edit`. The talk hotkey (Control-Option-Shift-Space, `.talk` in `Hotkey.swift`) calls `PanelController.talk()`, which opens the panel if needed and calls `toggleTalking`: the first press starts a `SpeechListener`, the next finishes it and sends what was heard. While listening, the field shows the text typed before plus what has been heard, the pill's edge breathes in blue, and a card above it shows bars that rise from the middle with the voice, over the hint "<talk shortcut> sends · esc cancels". The bars follow `Composer.level`, which comes from `.level` listener events: `SpeechListener.level(of:)` maps each audio buffer's loudness from -50 dB to -10 dB onto 0 to 1, about 20 times a second (the microphone tap takes 2048-frame buffers). The microphone button at the end of the field does what the talk hotkey does. Typing stops listening and keeps the text; Esc (`cancelTalking`) puts the field back and closes the panel; any other close (`stopTalking`) keeps the text unsent. The field also reports its own text back unchanged (on focus, after new words), which `edit` ignores so listening isn't stopped. Decision 16.

`SpeechListener` runs `SpeechAnalyzer` with a `SpeechTranscriber` for the Mac's language, on device (decision 17). Each press: microphone permission (`AVAudioApplication`), the speech model (downloaded on first use; the panel says "Downloading the speech model…"), then an `AVAudioEngine` input tap converted to the analyzer's format. Words arrive as `heard` events about once a second with `fastResults`; finishing finalizes the last words before the text is sent. It takes about 100 ms from the press to listening. Failures (microphone denied or missing, unsupported language, recognition errors) show in red under the field, and so does a press that heard nothing.

The `audioInputFile` user default replaces the microphone with a file, played in real time and then silence. UI tests set it (decision 18); `Info.plist` carries `NSMicrophoneUsageDescription`, without which macOS would kill Aside on first use of the microphone.

## Voice output

`Composer` sends a question with `aloud: true` when it was sent while listening (decision 19). `AssistantSession.send` then starts its `Narrator` on that exchange, and after every change to the conversation hands it the newest exchange. Sending without `aloud` stops whatever was being read.

`Narrator` turns the answer so far into spoken text (`SpokenText.prose`) and hands each new complete sentence to its `Speaker`. The last sentence waits for more text, unless the answer has ended or paused for a tool ("Let me check." is said before the search runs). It counts the characters already handed over, so each sentence is said once as the answer grows. `isReading` lasts from the question until the answer has ended and the speaker has said every sentence, or until `stop()`. Meanwhile its `caption` splits the spoken text into what was said, the sentence being said (the first one handed over and not yet said, since the speaker says them in order) and what's to come; the answer card shows it in place of the answer, the current sentence bright, with "Reading" and "Esc stops" chips under it. Once reading ends or stops, the card shows the formatted answer, code included.

`SpokenText.prose` works line by line: fenced code blocks, tables, rules and images are left out; heading, list and quote marks, emphasis and code backticks are dropped; links read as their text and bare web addresses as their site ("apple.com"). A complete line without closing punctuation gets a period, so list items get a pause. `NLTokenizer` splits sentences, so "Dr." and "$3.50" don't end one.

`SpeechSpeaker` queues each sentence on one `AVSpeechSynthesizer`, so sentences run together without gaps, in the voice from decision 20. `stop()` cuts off mid-word and drops the queue. Esc (`PanelController`), the talk hotkey (`Composer.startTalking`, so the microphone doesn't hear the answer), the next question and New conversation call it.

## Panel

`PanelView` is a column of Liquid Glass shapes in one `GlassEffectContainer`: from the bottom up, a capsule holding the field (the "pill"), while talking a card with the voice bars, a capsule for a problem (a voice failure, claude missing) when there is one, and a card with the newest answer. The window around them is transparent, with a 20-point margin for the listening glow. The glow is drawn over the container, not inside it, because the container draws its glass over its children's overlays. `PanelController.show()` puts the window in the bottom-right corner of the screen the pointer is on, above the Dock (decision 22). When SwiftUI resizes the window, `FloatingPanel.setFrame` keeps its bottom edge where it was, so the field stays in the corner and the answer grows upward.

`FloatingPanel` (`App/Sources/PanelController.swift`) is a borderless `NSPanel` with `.nonactivatingPanel`: it takes keyboard input without activating Aside, so the app the user was in stays frontmost. `.canJoinAllSpaces` and `.fullScreenAuxiliary` put it on the current Space and over full-screen apps. Esc (`cancelOperation`) and losing key status (a click outside) hide it. The app is `LSUIElement`: no Dock icon, just a menu bar item.

## Claude

The app runs the Claude Code CLI as a child process. There is no API key, and Anthropic's SDKs aren't involved.

- **Finding it.** GUI apps don't get the shell's PATH. `ClaudeLocator` (`AsideCore`) checks a configured path, then the common install locations, then asks the login shell.
- **Process model (M1).** One long-lived process per conversation:
  `claude -p --input-format stream-json --output-format stream-json --verbose --include-partial-messages --model sonnet --setting-sources project --strict-mcp-config --tools WebSearch,WebFetch --allowedTools WebSearch,WebFetch --permission-prompts host --permission-prompt-tool stdio --append-system-prompt <memory> --autocompact 150000`, plus `--resume <session id>` once there is a conversation to continue, with `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1` added to its environment. The tool flags come from `Tool.all` (see Tools); `--tools` is `WebSearch,WebFetch,Read,Edit,Write`, and `--allowedTools` adds the file tools for the memory folder only (see Memory).
  Each user message is one JSON line on stdin. Text arrives as `stream_event` lines with `content_block_delta` / `text_delta`, a `content_block_start` marks each new text block or tool use, and each turn ends with a `result` line. The process is started when the panel opens, so it is ready by the time the user has typed or spoken. When Aside quits, claude sees its stdin close and exits.
- **Reading output.** `ClaudeProcess` reads pipes with `readabilityHandler`, because `FileHandle.bytes` holds a pipe's output back until its buffer fills, and splits lines on `\n` only. It ignores `SIGPIPE`, so writing to a claude that just died throws instead of killing Aside.
- **Isolation.** The process runs in `<data>/workspace/`, where `<data>` is `~/Library/Application Support/Aside` (or `ASIDE_DATA_DIRECTORY` from the launch environment, which UI tests set). Aside rewrites the folder's `CLAUDE.md` each time claude starts; it sets the assistant's voice (short, speakable answers). `--setting-sources project` keeps the owner's own Claude Code settings, hooks, plugins and `~/.claude/CLAUDE.md` out (checked on 2026-10-15). `--strict-mcp-config` keeps their MCP servers out. `--tools` makes `Tool.all` the only tools, and `--allowedTools` approves the ones that don't ask first. `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1` turns off Claude Code's auto memory, which would otherwise put its own memory instructions in claude's prompt; Aside keeps its own memory instead (decision 26).
- **Configured path.** The `claudePath` user default, if set, is used instead of searching (`defaults write com.rigomart.aside claudePath /path/to/claude`). UI tests set it with a launch argument to point at `UITests/Support/fake-claude`.
- **Compaction threshold.** The `compactAfterTokens` user default replaces the 80,000 tokens at which Aside compacts. UI tests set it to 1 with a launch argument, to compact after every turn.
- **Calendar (M4).** First try the owner's claude.ai Google Calendar connector. `--strict-mcp-config` may hide connectors; check this before choosing an MCP config.

## Tools

`Tool.all` (`AsideCore/Tool.swift`) is the one list of claude's tools. Each `Tool` has claude's name for it, the panel's activity line ("Searching the web…"), how the workspace `CLAUDE.md` names it, an optional line for that file on when to use it, and `asksFirst`. `ClaudeProcess.arguments` puts every tool in `--tools` and the ones that don't ask first in `--allowedTools`; `Workspace.instructions()` writes those lines and "Your only tools are …"; `Conversation` looks up the activity line. Today the list is web search and web fetch, which don't ask, and `Read`, `Edit` and `Write`, which don't ask inside the memory folder (`allowedInMemory`) and ask everywhere else.

A tool with `asksFirst` waits for the owner each time (decision 24). claude writes a `control_request` with subtype `can_use_tool` on stdout (tool name, input, and a short `description`, such as a file name) and waits. `ClaudeEvent` parses it into `.approvalRequested(ApprovalRequest)`, and `Conversation` keeps it on the newest exchange as `approval`, so the answer is still "responding": a question sent meanwhile is ignored. The answer card shows "Allow <tool>?", the description, and Deny and Allow buttons. No key answers it, so a Return meant for the field can't allow something. `AssistantSession.answerApproval(allow:)` writes a `control_response`: allow sends the input back unchanged as `updatedInput`; deny sends "The owner declined.", which claude sees as the tool's result and says so in its answer. Esc and clicking outside close the panel with the request still waiting; New conversation stops claude, and the request with it. Answers read aloud stop at the sentence before the tool; the request itself isn't read.

`ClaudeProcess` answers any other `control_request` with an error ("Aside doesn't handle <kind> requests.") and logs it, so claude never waits on Aside for something the panel doesn't show.

Checked with Claude Code 2.1.316 on 2026-11-03: `--permission-prompts host` alone denies tools that would ask ("you haven't granted it yet"); `--permission-prompt-tool stdio` is what sends the request to stdout. Allowing ran the tool, and denying stopped it.

Adding a tool:

1. Add it to `Tool.all`. A claude built-in (`Write`, `Read`) only needs its name. An MCP server also needs `--mcp-config` in `ClaudeProcess.arguments`, since `--strict-mcp-config` loads none of the owner's.
2. Give it `asksFirst: true` if it changes anything outside Aside (an event, a note).
3. When "Allow <tool>?" and the CLI's description don't say clearly what will happen, make the prompt from the tool's input (`ApprovalRequest.input`, JSON).
4. Prove it with a UI test against the real claude (`launch()`), since the fake one ignores the flags, and copy `UITests/Tests/ApprovalTests.swift` for the panel.

## Memory

`Memory` (`AsideCore`) is `<data>/memory/MEMORY.md`: a short header, then one fact per line starting with "- ", such as "- Your sister is named Ana." `Memory.load` creates the folder and file if they're missing. Decision 26.

- **Loading.** `AssistantSession.connect` loads the memory before each claude start. `ClaudeProcess.arguments` puts its facts in `--append-system-prompt` and allows `Read`, `Edit` and `Write` under the folder (`Read(//<folder>/**)` and so on). `Workspace.instructions` tells claude where the file is, what to save, and to remove a line when asked to forget. A process sees facts saved before it started; facts saved during a conversation are in that conversation's context anyway.
- **Saving.** claude reads the file, then edits it with `Edit`. The activity line says "Checking memory…" and then "Remembering…". A file tool used anywhere else waits for Allow in the panel (decision 24), with the path as its detail.
- **Opening.** The menu bar item's Open Memory (`AppDelegate.openMemory`) loads the memory, which creates the file if needed, and opens it in TextEdit. A failure shows in an alert (decision 27).
- **Showing.** `AssistantSession` keeps the memory as it was when the question was sent. On every output except answer text (a tool starting, a text block starting, the turn ending, claude exiting) it reads the file again, and `Memory.changes` turns the difference into "Remembered: <fact>" and "Forgot: <fact>", added to the exchange's `memoryNotes`. The answer card lists them under the answer. The narrator reads only the answer, so they are never read aloud. Because the notes come from the file, a write that failed or was denied shows nothing. If the file can't be read, the card says "Couldn't read memory: <reason>" once, and the next good read picks up from the last one that worked.

## Build and signing

- XcodeGen generates the project from `project.yml`.
- Builds are signed with the owner's Apple Development certificate (team `WHZ7FDCNMT`). Privacy grants follow the signature, so a stable identity means microphone and speech permissions survive rebuilds. There is no hardened runtime, no sandbox (a sandboxed app can't spawn `claude`), and no notarization.
- The bundle ID is `com.rigomart.aside`.
- The `Verify` build configuration builds Aside Verify for UI tests: bundle ID `com.rigomart.aside.verify`, URL scheme `aside-verify://`. It runs beside the owner's copy without sharing defaults, privacy grants or `aside://`. UI tests give it the hotkeys Control-Option-Command-Space (open) and Control-Option-Shift-Command-Space (talk) through launch arguments, because Carbon hotkeys aren't exclusive and a shared one would open both panels.
- `AsideUITests` (sources in `UITests/`) has its own scheme with the `Verify` configuration, so `make check` never runs it. `scripts/verify` builds and runs it into `.verify/<instance>/`.
