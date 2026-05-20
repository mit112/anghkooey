import OSLog

public enum UILog {
    public nonisolated(unsafe) static var subsystem: String = "com.unknown.anghkooey"

    public static var review: Logger { Logger(subsystem: subsystem, category: "Review") }
    public static var library: Logger { Logger(subsystem: subsystem, category: "Library") }
    public static var capture: Logger { Logger(subsystem: subsystem, category: "Capture") }
}
