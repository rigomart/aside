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

## Voice input (M2)

1. In any app, press Control-Option-Shift-Space. The first time, macOS asks to let Aside use the microphone: allow it. If the panel closed when the prompt appeared, press Control-Option-Shift-Space again. The panel opens with a red "Listening…" line under the field, and the app you were in stays active.
2. Say "What's the weather in Lima today?". Your words appear in the field as you speak, and the last few may change as it catches up. Press Control-Option-Shift-Space: the question is sent and answered.
3. Talk again and press Return instead: it sends just the same.
4. Talk, then press Esc: the panel closes. Reopen it with Control-Option-Space: the field is empty, and nothing was sent.
5. Talk, then type a word: the "Listening…" line goes away, the menu bar's orange microphone dot goes out, and your typing is added to what was heard.
6. Talk, then press Control-Option-Space: the panel closes and the microphone dot goes out. Reopen: what you said is in the field, unsent.
7. Press Control-Option-Shift-Space and say nothing, then press it again: "Didn't hear anything." shows and nothing is sent.
8. With AirPods or another headset connected, talk: it hears you through the headset.
9. Talk with music or other people in the room: does it pick up your question well enough? Note anything it gets wrong.
10. In System Settings › Privacy & Security › Microphone, turn Aside off (reopen Aside if macOS asks you to quit it), then talk: the panel says Aside can't use the microphone and where to allow it. Turn it back on.
