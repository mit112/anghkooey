import OSLog

/// OSLog factory for the AnghkooeyIntelligence package.
///
/// Set `subsystem` once at app startup (e.g. in `@main`) before any log call.
/// Defaults to `"com.unknown.anghkooey"` so package tests work without an app host.
public enum IntelligenceLog {
    /// The OSLog subsystem identifier. Set this to your bundle ID at launch.
    public nonisolated(unsafe) static var subsystem: String = "com.unknown.anghkooey"

    /// Logger for the on-device AI (FoundationModels) subsystem.
    public static var ai: Logger { Logger(subsystem: subsystem, category: "AI") }
    /// Logger for the Vision OCR subsystem.
    public static var ocr: Logger { Logger(subsystem: subsystem, category: "OCR") }
    /// Logger for the FoundationModels card authoring subsystem.
    public static var authoring: Logger { Logger(subsystem: subsystem, category: "Authoring") }

    /// Shared `OSSignposter` for intelligence-pipeline latency intervals.
    ///
    /// Uses `"PointsOfInterest"` so intervals appear alongside Core's signposts
    /// on the same Instruments Points of Interest track. Interval names:
    /// `"ai-draft-generation"`.
    public static var poiSignposter: OSSignposter {
        OSSignposter(subsystem: subsystem, category: "PointsOfInterest")
    }
}
