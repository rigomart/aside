# Manual tests

Checks no automated test can reach. Run the section for the milestone being handed over, plus anything an agent names in its report. Start each from `make run`, with Aside not already running elsewhere.

## Panel (M0)

1. Press Control-Option-Space in any app: the panel appears near the top of the screen the pointer is on, with the cursor in the text field.
2. Type: text goes into the panel. The app you were in still shows as active in the menu bar.
3. Press Esc: the panel closes, and typing goes back to the app you were in.
4. Open the panel and click outside it: it closes.
5. Put Safari in full screen and press the hotkey: the panel appears over it.
6. Switch to another desktop (Space) and press the hotkey: the panel appears on that Space, not the old one.
7. Press the hotkey twice: it opens, then closes.
8. Menu bar: the speech-bubble icon shows; "Show Aside" opens the panel; "Quit Aside" quits.
9. The line under the field shows `claude: <path>`, not "not found".

## Text loop (M1)

1. Open the panel, type a question and press Return: the field clears, "Thinking…" shows, then the answer appears a few words at a time.
2. Ask a follow-up that only makes sense with the first answer ("shorter, please"): it answers in context.
3. Ask something that needs the web ("what's the weather in Paris right now?"): "Searching the web…" shows, then the answer.
4. Copy a sentence and paste it into the field with Command-V. Select part of an answer with the mouse and copy it with Command-C: it pastes elsewhere.
5. Ask for something long, press Esc while it's still answering, wait a few seconds, reopen: the full answer is there.
6. Put Safari in full screen, open the panel and ask something long: the panel grows downward over Safari, then scrolls.
7. Press Command-N: the panel empties. Ask "what did I just ask you?": it doesn't know.
8. After an answer, leave the panel closed for over 10 minutes, then reopen: the panel is empty.
