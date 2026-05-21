import OSLog

/// Centralised `Logger` factory for AnghkooeyCore.
///
/// All loggers share a single `subsystem` string so Instruments and
/// Console can filter by app. The subsystem must be injected by the app
/// composition root (or the Share Extension host) before any log call fires;
/// the default placeholder keeps the compiler happy but will appear in
/// Console if the injection step is skipped.
public enum CoreLog {
    /// OSLog subsystem identifier, shared across all `Logger` instances.
    ///
    /// Set this once at app launch — e.g. `CoreLog.subsystem = Bundle.main.bundleIdentifier ?? "com.unknown.anghkooey"`.
    /// Defaults to `"com.unknown.anghkooey"` so the package compiles without a
    /// host app, but production builds should always inject the real bundle ID.
    public nonisolated(unsafe) static var subsystem: String = "com.unknown.anghkooey"

    /// Logger for the FSRS-6 scheduling subsystem (category `"Scheduling"`).
    public static var scheduling: Logger { Logger(subsystem: subsystem, category: "Scheduling") }

    /// Logger for the SwiftData persistence subsystem (category `"Persistence"`).
    public static var persistence: Logger { Logger(subsystem: subsystem, category: "Persistence") }

    /// Logger for the capture-inbox pipeline (category `"CaptureInbox"`).
    public static var captureInbox: Logger { Logger(subsystem: subsystem, category: "CaptureInbox") }
}
