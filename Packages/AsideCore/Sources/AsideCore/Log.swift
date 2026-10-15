import os

/// Loggers for the app. Read them with `make logs`.
public enum Log {
    public static let subsystem = "com.rigomart.aside"

    public static let app = Logger(subsystem: subsystem, category: "app")
    public static let panel = Logger(subsystem: subsystem, category: "panel")
    public static let claude = Logger(subsystem: subsystem, category: "claude")
}
