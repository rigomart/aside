# Feature map

Each user-visible feature, the committed examples that drive it, and what no example drives yet. Copy from them when you write the test that proves your change. An example's test names say what it drives; read the test for how.

| Feature | Behavior | Examples | Not covered |
| --- | --- | --- | --- |
| Open with the hotkey | Control-Option-Space (Control-Option-Shift-Space in Aside Verify) opens the panel over the app in front, with the cursor in the field; that app stays active and typing goes into the panel. | [testHotkeyOpensPanelOverFrontApp](../../../../UITests/Tests/PanelTests.swift), through `pressHotkey` in [AppActions.swift](../../../../UITests/Support/AppActions.swift) | The default Control-Option-Space itself; which display it opens on; full-screen apps and other Spaces (manual) |
| Close the panel | Esc closes it; pressing the hotkey again closes it; clicking outside closes it. | [testHotkeyOpensPanelOverFrontApp](../../../../UITests/Tests/PanelTests.swift) (Esc), [testMenuBarOpensPanelAndHotkeyClosesIt](../../../../UITests/Tests/PanelTests.swift) (hotkey) | Click outside; typing going back to the previous app after closing, which XCUITest can't show (manual test 3) |
| Menu bar item | The speech-bubble icon's menu has Show Aside, which opens the panel, and Quit Aside. | [testMenuBarOpensPanelAndHotkeyClosesIt](../../../../UITests/Tests/PanelTests.swift), through `openPanelFromMenuBar` | Quit Aside |
| URL scheme | `aside://show`, `hide` and `toggle` open, close and toggle the panel (`aside-verify://` in Aside Verify). | Every test that uses `openPanelWithURL` (`show`); `openURL` in [AppActions.swift](../../../../UITests/Support/AppActions.swift) sends any action | `hide` and `toggle`; an unknown URL; LaunchServices routing of `aside://` |
| claude status line | The line under the field shows `claude: <path>`, or that claude was not found. | [testPanelShowsWhereClaudeIs](../../../../UITests/Tests/PanelTests.swift) | claude missing: no setting can point Aside at a missing path yet |

## Keeping it current

A row changes when an example is added, moved into `UITests/Tests/`, or deleted, or when a feature appears or goes away. Milestone 1 (sending a question and streaming the answer) adds the first feature that needs a stand-in for `claude`, at a seam the owner could also set, such as the path setting the status line mentions.
