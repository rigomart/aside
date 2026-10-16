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
| 0 | Setup: project, build, hotkey and panel shell, docs, latency measured | Done |
| 1 | Text loop: type, streamed answer, follow-ups in one conversation, process started on hotkey press | Done, pending the owner's manual checks |
| 2 | Voice input: talk hotkey, live transcript in the field, the second press sends | Done, pending the owner's manual checks |
| 3 | Voice output: sentence by sentence, skips markdown and code, interruptible | Done, pending the owner's manual checks |
| 4 | Tools: calendar read and create with confirmation in the panel, notes | Next |
| 5 | Polish: settings, launch at login | |

Each milestone ends with a short checklist in [manual-tests.md](manual-tests.md) that the owner runs.

## Open product decisions

Defaults agents use until the owner decides. Move each to [decisions.md](decisions.md) once settled.

| Question | Default |
| --- | --- |
| Which language does Aside listen in? | The Mac's language (English); no switching |
| Where do notes go? | A Markdown folder the owner picks |
| Creating calendar events: confirm first, or create and offer undo? | Confirm in the panel |
