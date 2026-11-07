import AppKit
import AsideCore
import ServiceManagement

/// Launch at Login, through `SMAppService.mainApp`. Only the copy in /Applications has it: the menu bar item's
/// Launch at Login turns it on and off, and the first launch turns it on (decision 29).
enum LoginItem {
    /// Set once Aside or the owner has turned it on or off, so Aside never turns it back on by itself.
    private static let setKey = "launchAtLoginSet"

    static var isAvailable: Bool {
        LaunchAtLogin.isInstalled(Bundle.main.bundleURL)
    }

    static var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    static func turnOnIfFirstInstalledLaunch() {
        let alreadySet = UserDefaults.standard.bool(forKey: setKey)
        guard LaunchAtLogin.turnsOnByItself(app: Bundle.main.bundleURL, alreadySet: alreadySet) else { return }
        Log.app.info("First launch from /Applications: turning on Launch at Login")
        set(true)
    }

    /// The menu item: off when on, on when off, and to System Settings while macOS waits for the owner's approval.
    static func toggle() {
        switch status {
        case .enabled: set(false)
        case .requiresApproval: askForApproval()
        default: set(true)
        }
    }

    /// A failure, or macOS waiting for the owner's approval, shows in an alert. Only a change that took is
    /// remembered, so a failed first launch tries again on the next.
    private static func set(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Log.app.error("Launch at Login \(on ? "on" : "off", privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return alert("Couldn't turn Launch at Login \(on ? "on" : "off")", error.localizedDescription)
        }
        UserDefaults.standard.set(true, forKey: setKey)
        Log.app.info("Launch at Login status: \(status.rawValue, privacy: .public)")
        if on, status == .requiresApproval {
            askForApproval()
        }
    }

    private static func askForApproval() {
        alert("Allow Aside to open at login", "Turn Aside on in System Settings › General › Login Items & Extensions.")
        SMAppService.openSystemSettingsLoginItems()
    }

    private static func alert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        NSApp.activate()
        alert.runModal()
    }
}
