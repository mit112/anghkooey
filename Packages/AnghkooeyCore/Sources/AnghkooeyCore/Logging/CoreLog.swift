import OSLog

public enum CoreLog {
    /// Injected by the app composition root at startup. Avoids reading Bundle.main
    /// (which resolves to the extension bundle inside the Share Extension and
    /// would silently split logs across two subsystems).
    public nonisolated(unsafe) static var subsystem: String = "com.unknown.anghkooey"

    public static var scheduling: Logger { Logger(subsystem: subsystem, category: "Scheduling") }
    public static var persistence: Logger { Logger(subsystem: subsystem, category: "Persistence") }
    public static var captureInbox: Logger { Logger(subsystem: subsystem, category: "CaptureInbox") }
}
