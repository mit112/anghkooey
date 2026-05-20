import OSLog

public enum IntelligenceLog {
    public nonisolated(unsafe) static var subsystem: String = "com.unknown.anghkooey"

    public static var ai: Logger { Logger(subsystem: subsystem, category: "AI") }
    public static var ocr: Logger { Logger(subsystem: subsystem, category: "OCR") }
}
