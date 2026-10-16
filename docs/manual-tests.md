# Manual tests

Checks no automated test can reach: the real microphone, how something looks or feels, full-screen apps, Spaces, and focus going back to other apps. A step that a unit or UI test already proves doesn't belong here; the agent's report lists what tests proved. Run the section for the milestone being handed over, plus anything an agent names in its report. Start each from `make run`, with Aside not already running elsewhere.

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

UI tests prove asking, follow-ups, web search, Esc mid-answer, Command-V and Command-N; the idle reset is unit-tested.

1. Ask for something long: the answer appears a few words at a time, at a pace that reads comfortably.
2. Select part of an answer with the mouse, press Command-C, and paste it into another app.
3. Put Safari in full screen, open the panel and ask something long: the panel grows downward over Safari, then scrolls.

## Voice input (M2)

UI tests prove the talk hotkey, words appearing as they're heard, sending with the second press or Return, Esc, typing, closing, and failures, with a recorded clip standing in for the microphone. These steps cover the microphone itself.

1. In any app, press Control-Option-Shift-Space. The first time, macOS asks to let Aside use the microphone: allow it. If the panel closed when the prompt appeared, press Control-Option-Shift-Space again.
2. Ask something out loud, such as "What's the weather in Lima today?": your words appear in the field as you speak and match what you said. Press Control-Option-Shift-Space to send it.
3. While it listens, the orange microphone dot shows in the menu bar. After it sends, and after Esc, the dot goes out.
4. With AirPods or another headset connected, talk: it hears you through the headset.
5. Talk with music or other people in the room: note anything it gets wrong.
6. In System Settings › Privacy & Security › Microphone, turn Aside off (reopen Aside if macOS asks you to quit it), then talk: the panel says Aside can't use the microphone and where to allow it. Turn it back on.

## Voice output (M3)

UI tests prove that a spoken question's answer is read and a typed one's isn't, that the "Reading aloud" line goes away once the answer has been said, and that Esc and the talk hotkey stop reading while closing with the hotkey doesn't. Unit tests prove which text is said, sentence by sentence. These steps cover the sound itself.

1. Press Control-Option-Shift-Space and ask out loud for something with a few sentences, such as "Give me three tips for sleeping better". Send it with Control-Option-Shift-Space: Aside starts speaking soon after the first sentence appears, before the answer is finished, and reads it to the end with no long gaps between sentences.
2. Listen for symbols: it never says "asterisk", "hash", "backtick", "dash" or a web address letter by letter. Ask out loud "Show me the Terminal command to list files, in a code block, then say one more sentence": it skips the command and reads the sentence after it.
3. Type a question and press Return: the answer appears and nothing is read.
4. Ask out loud for something long, then press Esc mid-sentence: speech stops at once.
5. Ask out loud for something long, close the panel with Control-Option-Space and go back to your app: it keeps reading. Press Control-Option-Shift-Space while it reads: it stops at once and listens, and the words in the field are yours, not the answer's.
6. With AirPods connected, ask out loud: the answer plays in the AirPods.
7. Note whether the voice sounds good enough. If not, download a Premium voice for English (US) in System Settings › Accessibility › Spoken Content › System Voice › Manage Voices, quit and reopen Aside, and ask again.

