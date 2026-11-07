import Foundation

/// Which copy of Aside has Launch at Login, and when it turns it on without being asked (decision 29).
public enum LaunchAtLogin {
    /// The folder `make install` puts Aside in.
    public static let installFolder = URL(fileURLWithPath: "/Applications", isDirectory: true)

    /// Whether this copy is the installed one. Only it shows Launch at Login, since copies built in a checkout
    /// share its bundle ID and would turn the owner's login item on or off.
    public static func isInstalled(_ app: URL) -> Bool {
        app.deletingLastPathComponent().standardizedFileURL.path == installFolder.path
    }

    /// The first time the installed copy starts. Once the owner or Aside has set it, Aside leaves it alone.
    public static func turnsOnByItself(app: URL, alreadySet: Bool) -> Bool {
        !alreadySet && isInstalled(app)
    }
}
