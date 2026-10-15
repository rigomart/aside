import AppKit
import AsideCore
import KeyboardShortcuts

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let session = AssistantSession(
        dataDirectory: AppDelegate.dataDirectory,
        claudePath: UserDefaults.standard.string(forKey: "claudePath")
    )
    private lazy var panel = PanelController(session: session)
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = makeStatusItem()
        NSApp.mainMenu = makeEditMenu()
        KeyboardShortcuts.onKeyUp(for: .togglePanel) { [weak self] in
            self?.panel.toggle()
        }
        Log.app.info("Launched")
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

    private func makeStatusItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "text.bubble", accessibilityDescription: "Aside")
        let menu = NSMenu()
        menu.addItem(withTitle: "Show Aside", action: #selector(showPanel), keyEquivalent: "").target = self
        menu.addItem(.separator())
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

    @objc private func showPanel() {
        panel.show()
    }
}
