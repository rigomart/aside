import AppKit
import AsideCore
import KeyboardShortcuts

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let session = AssistantSession(
        dataDirectory: AppDelegate.dataDirectory,
        claudePath: UserDefaults.standard.string(forKey: "claudePath"),
        speaker: SpeechSpeaker(),
        compactAt: AppDelegate.compactAt
    )
    private lazy var composer = Composer(session: session) {
        SpeechListener(source: AppDelegate.audioSource)
    }
    private lazy var panel = PanelController(session: session, composer: composer)
    private lazy var dictation = DictationController(shownFor: AppDelegate.dictationMessageTime) {
        SpeechListener(source: AppDelegate.audioSource)
    }
    private var statusItem: NSStatusItem?
    private var launchAtLoginItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = makeStatusItem()
        NSApp.mainMenu = makeEditMenu()
        KeyboardShortcuts.onKeyUp(for: .togglePanel) { [weak self] in
            self?.panel.toggle()
        }
        KeyboardShortcuts.onKeyUp(for: .talk) { [weak self] in
            self?.panel.talk()
        }
        KeyboardShortcuts.onKeyUp(for: .dictate) { [weak self] in
            self?.dictate()
        }
        panel.onShow = { [weak self] in
            self?.dictation.cancel()
        }
        LoginItem.turnOnIfFirstInstalledLaunch()
        Log.app.info("Launched from \(Bundle.main.bundlePath, privacy: .public)")
    }

    /// `aside://show`, `aside://hide`, `aside://toggle`. Lets scripts, Shortcuts, and
    /// verification tests open the panel without the hotkey.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            switch url.host() {
            case "show": panel.show()
            case "hide": panel.hide()
            case "toggle": panel.toggle()
            default: Log.app.error("Unknown URL: \(url.absoluteString, privacy: .public)")
            }
        }
    }

    /// `~/Library/Application Support/Aside`, or `ASIDE_DATA_DIRECTORY` from the launch environment,
    /// which UI tests set so they never share the owner's data.
    private static var dataDirectory: URL {
        if let path = ProcessInfo.processInfo.environment["ASIDE_DATA_DIRECTORY"] {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return URL.applicationSupportDirectory.appending(path: "Aside", directoryHint: .isDirectory)
    }

    /// 80,000 tokens, or the `compactAfterTokens` user default, which UI tests set low to see a compaction
    /// without a long conversation.
    private static var compactAt: Int {
        let tokens = UserDefaults.standard.integer(forKey: "compactAfterTokens")
        return tokens > 0 ? tokens : 80_000
    }

    /// How long dictation's messages stay, or the `dictationMessageSeconds` user default for all of them, which
    /// UI tests set long because each hotkey press takes XCUITest about 10 s.
    private static var dictationMessageTime: @Sendable (Dictation.Message) -> Duration {
        let seconds = UserDefaults.standard.integer(forKey: "dictationMessageSeconds")
        guard seconds > 0 else { return { Dictation.shownFor($0) } }
        return { _ in .seconds(seconds) }
    }

    /// The microphone, or the `audioInputFile` user default: an audio file heard as if spoken.
    /// UI tests set it with a launch argument, since they can't talk.
    private static var audioSource: SpeechListener.Source {
        UserDefaults.standard.string(forKey: "audioInputFile").map { .file(URL(fileURLWithPath: $0)) } ?? .microphone
    }

    private func makeStatusItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "text.bubble", accessibilityDescription: "Aside")
        let menu = NSMenu()
        menu.addItem(withTitle: "Show Aside", action: #selector(showPanel), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Open Memory", action: #selector(openMemory), keyEquivalent: "").target = self
        menu.addItem(.separator())
        if LoginItem.isAvailable {
            let launchAtLogin = menu.addItem(withTitle: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
            launchAtLogin.target = self
            launchAtLoginItem = launchAtLogin
            menu.addItem(.separator())
            menu.delegate = self
        }
        menu.addItem(withTitle: "Quit Aside", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        return item
    }

    /// Never shown, since Aside has no menu bar of its own, but text fields get Command-X, C, V, A and Z
    /// from these items' shortcuts.
    private func makeEditMenu() -> NSMenu {
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let main = NSMenu()
        main.addItem(withTitle: "Edit", action: nil, keyEquivalent: "").submenu = edit
        return main
    }

    /// The dictation hotkey. Closes the panel and stops reading aloud, so the microphone hears only the owner.
    private func dictate() {
        panel.hide()
        session.stopReadingAloud()
        dictation.toggle()
    }

    /// Shows whether Launch at Login is on each time the menu opens, since System Settings can change it. A dash
    /// means macOS is waiting for the owner to allow it there.
    func menuWillOpen(_ menu: NSMenu) {
        launchAtLoginItem?.state = switch LoginItem.status {
        case .enabled: .on
        case .requiresApproval: .mixed
        default: .off
        }
    }

    @objc private func toggleLaunchAtLogin() {
        LoginItem.toggle()
    }

    @objc private func showPanel() {
        panel.show()
    }

    /// Opens MEMORY.md, created if Aside hasn't saved anything yet, so the owner can read and edit what
    /// Aside remembers. In TextEdit rather than the default app for .md files, which may be Xcode.
    @objc private func openMemory() {
        guard let textEdit = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") else {
            return showMemoryProblem("TextEdit isn't installed.")
        }
        Task {
            do {
                let file = try Memory.load(in: Self.dataDirectory).file
                _ = try await NSWorkspace.shared.open([file], withApplicationAt: textEdit, configuration: NSWorkspace.OpenConfiguration())
            } catch {
                showMemoryProblem(error.localizedDescription)
            }
        }
    }

    private func showMemoryProblem(_ message: String) {
        Log.app.error("Couldn't open memory: \(message, privacy: .public)")
        let alert = NSAlert()
        alert.messageText = "Couldn't open memory"
        alert.informativeText = message
        NSApp.activate()
        alert.runModal()
    }
}
