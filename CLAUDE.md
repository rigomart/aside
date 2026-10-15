# Aside

A personal macOS assistant. A global hotkey opens a floating panel over whatever app is in front; the owner types or speaks, and Claude answers in the panel and can read the answer aloud. Claude runs through the Claude Code CLI on the owner's subscription. Personal use only: macOS 26+, not sandboxed, not notarized.

The owner makes product decisions and does not read or review code. You own the code: keep it small and plain enough that the next agent understands it cold, and prove your changes yourself.

## Commands

| Command | Does |
| --- | --- |
| `make check` | Build the app and run the core tests. Must pass before you finish. |
| `make test` | Core package tests only (`swift test`, seconds). |
| `make run` | Build, quit any running copy, launch. |
| `make logs` | Stream the app's logs (`os.Logger`, subsystem `com.rigomart.aside`). |
| `make generate` | Regenerate `Aside.xcodeproj` from `project.yml`. `build` does this. |
| `open aside://show` | Open the panel without the hotkey (`hide`, `toggle` also work). |

The Makefile sets `DEVELOPER_DIR` to `/Applications/Xcode.app`; the system `xcode-select` points at the Command Line Tools. Call `xcodebuild` through `make` or with that variable set.

## Layout

- `App/Sources/`: the app target. AppKit and SwiftUI glue: panel, hotkey, menu bar item, URL handling.
- `Packages/AsideCore/`: logic that needs no AppKit, with Swift Testing tests. The app depends on it.
- `project.yml`: XcodeGen spec. `Aside.xcodeproj` and `App/Info.plist` are generated and gitignored.
- `docs/`: product, architecture, decisions, manual tests. Read the ones your task touches.
- `scripts/stop-check.sh`: Stop hook that runs `make check` when sources changed.

## Rules

- Never edit `Aside.xcodeproj` or `App/Info.plist`. Change `project.yml`; files under `App/Sources` and the package are picked up automatically.
- Put logic that doesn't need AppKit in `AsideCore` and test it there. Keep the app target thin.
- Swift 6 language mode with complete concurrency checking. The app target defaults to `MainActor` isolation; the package does not. Fix warnings; don't silence them.
- Log through `Log.<category>`. Logs explain behavior; they don't prove it.
- No silent fallbacks: a missing `claude`, a failed process, or a denied permission shows up in the panel.
- Adding a package is the owner's decision. Propose it with the reason and the alternative.
- Record architecture and product decisions in `docs/decisions.md`. Ask the owner product questions as a choice with your recommended default, in terms of what they will see.

## Done means

1. `make check` passes.
2. The change is proven in the running app. Once `.claude/skills/verify-aside` exists, follow it. Until then, run the app, drive the change, and say exactly what you saw and what you couldn't check.
3. Behavior no test can reach (Spaces, full-screen apps, focus, sound) has steps in `docs/manual-tests.md`, and your report tells the owner which ones to run.
4. Docs that your change made wrong are updated.
