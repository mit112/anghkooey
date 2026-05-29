import OSLog

/// Centralised `Logger` factory for AnghkooeyCore.
///
/// All loggers share a single `subsystem` string so Instruments and
/// Console can filter by app. The subsystem must be injected by the app
/// composition root (or the Share Extension host) before any log call fires;
/// the default placeholder keeps the compiler happy but will appear in
/// Console if the injection step is skipped.
public enum CoreLog {
    private nonisolated(unsafe) static var _subsystem: String = "com.unknown.anghkooey"

    /// Inject the host app's bundle identifier before any log call fires.
    ///
    /// Call once from the app's `@main` entry point, e.g.:
    /// ```swift
    /// CoreLog.configure(subsystem: Bundle.main.bundleIdentifier ?? "com.unknown.anghkooey")
    /// ```
    /// Defaults to `"com.unknown.anghkooey"` so the package compiles without a
    /// host app, but production builds should always inject the real bundle ID.
    /// Subsequent calls are ignored; subsystem is write-once.
    public static func configure(subsystem: String) {
        guard _subsystem == "com.unknown.anghkooey" else { return }
        _subsystem = subsystem
    }

    internal static var subsystem: String { _subsystem }

    /// Logger for the FSRS-6 scheduling subsystem (category `"Scheduling"`).
    public static var scheduling: Logger { Logger(subsystem: subsystem, category: "Scheduling") }

    /// Logger for the SwiftData persistence subsystem (category `"Persistence"`).
    public static var persistence: Logger { Logger(subsystem: subsystem, category: "Persistence") }

    /// Logger for the capture-inbox pipeline (category `"CaptureInbox"`).
    public static var captureInbox: Logger { Logger(subsystem: subsystem, category: "CaptureInbox") }

    /// Logger for the Anki import pipeline (category `"AnkiImport"`).
    public static var ankiImport: Logger { Logger(subsystem: subsystem, category: "AnkiImport") }

    /// Shared `OSSignposter` for capture-pipeline latency intervals.
    ///
    /// Uses the `"PointsOfInterest"` category so intervals appear in the
    /// Instruments **Points of Interest** track. Interval names used by
    /// M3 capture: `"inbox-drain"`, `"share-tap-to-inbox-write"`,
    /// `"card-review-sheet-ready"`.
    public static var poiSignposter: OSSignposter {
        OSSignposter(subsystem: subsystem, category: "PointsOfInterest")
    }
}
