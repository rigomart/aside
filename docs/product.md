# Product

## What it is

A hotkey opens a small floating panel over whatever the owner is doing. They type or speak a request; the answer streams into the panel as text and can be read aloud. The app they were in keeps focus, so dismissing the panel puts them right back.

Main uses: quick lookups, the calendar (read and create events), brainstorming, and writing notes.

## Why build it

The Claude desktop app's quick entry opens the full app. ChatGPT's Option-Space now opens Codex, and its voice mode is a separate window. Atticus (open source, Claude subscription, overlay with voice) is the closest; it serves as a reference, not a base.

## Not in scope

- Other people. No App Store, no notarization, no onboarding, no settings for things only the owner would change once.
- Platforms other than macOS 26+.
- An API key or any billing besides the owner's Claude subscription.

## Milestones

| # | Milestone | Status |
| --- | --- | --- |
| 0 | Setup: project, build, hotkey and panel shell, docs, latency measured | Done, pending the owner's manual checks |
| 1 | Text loop: type, streamed answer, follow-ups in one conversation, process started on hotkey press | Next |
| 2 | Voice input: live transcript, sends when you stop talking | |
| 3 | Voice output: sentence by sentence, skips markdown and code, interruptible | |
| 4 | Tools: calendar read and create with confirmation in the panel, notes | |
| 5 | Polish: settings, launch at login | |

Each milestone ends with a short checklist in [manual-tests.md](manual-tests.md) that the owner runs.

## Open product decisions

Defaults agents use until the owner decides. Move each to [decisions.md](decisions.md) once settled.

| Question | Default |
| --- | --- |
| Voice trigger: hold the hotkey to talk, or tap and stop on silence? | Tap, stop on silence |
| Model: Haiku for speed or Sonnet for quality? | Sonnet. Measured first-token latency is about the same (see decisions) |
| Where do notes go? | A Markdown folder the owner picks |
| Creating calendar events: confirm first, or create and offer undo? | Confirm in the panel |
| When does a new conversation start? | After 10 minutes idle, or on request |
| Read answers aloud by default? | Only when the question was spoken |
