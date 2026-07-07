import AppIntents
import Foundation
import OSLog
import AnghkooeyCore

/// Widget extensions run in their own process, so `CoreLog`'s injected
/// subsystem (set by the main app's `AnghkooeyApp.init`) is never configured
/// here. Build a standalone `Logger` instead of relying on `CoreLog`.
private var log: Logger {
    Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.unknown.anghkooey", category: "Widget")
}

struct GradeCardIntent: AppIntent {
    nonisolated(unsafe) static var title: LocalizedStringResource = "Grade Card"
    nonisolated(unsafe) static var openAppWhenRun: Bool = false

    @Parameter(title: "Card ID")
    var cardID: String

    @Parameter(title: "Rating")
    var ratingRaw: Int

    func perform() async throws -> some IntentResult {
        guard let uuid = UUID(uuidString: cardID),
              let rating = Rating(rawValue: ratingRaw) else {
            log.error("Dropped widget grade: unparseable cardID/rating (cardID=\(cardID, privacy: .public), rating=\(ratingRaw, privacy: .public))")
            return .result()
        }
        let containerURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: InboxConstants.appGroupID)
            ?? FileManager.default.temporaryDirectory
        let bridge = WidgetBridge(containerURL: containerURL)
        do {
            try bridge.appendGrade(WidgetGradeDecision(id: UUID(), cardID: uuid, rating: rating, decidedAt: .now))
        } catch {
            log.error("widget grade append failed: \(error.localizedDescription, privacy: .public)")
        }
        return .result()
    }
}
