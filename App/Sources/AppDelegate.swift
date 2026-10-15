import AppKit
import AsideCore
import KeyboardShortcuts

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = PanelModel()
    private lazy var panel = PanelController(model: model)
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = makeStatusItem()
        KeyboardShortcuts.onKeyUp(for: .togglePanel) { [weak self] in
            self?.panel.toggle()
        }
        Task { await locateClaude() }
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

    private func locateClaude() async {
        let path = await Task.detached { ClaudeLocator.live.locate() }.value
        model.claude = path.map(PanelModel.ClaudeStatus.found) ?? .missing
        Log.claude.info("claude: \(path ?? "not found", privacy: .public)")
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

    @objc private func showPanel() {
        panel.show()
    }
}
