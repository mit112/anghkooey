import AppIntents
import Foundation
import OSLog
import WidgetKit
import AnghkooeyCore

/// Widget extensions run in their own process, so `CoreLog`'s injected
/// subsystem (set by the main app's `AnghkooeyApp.init`) is never configured
/// here. Build a standalone `Logger` instead of relying on `CoreLog`.
private var log: Logger {
    Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.unknown.anghkooey", category: "Widget")
}

/// Reveals the current card's answer in place, before Again/Good are shown.
/// Purely local to the widget's shared-container snapshot — never touches
/// the store or `grades.jsonl`.
struct RevealAnswerIntent: AppIntent {
    nonisolated(unsafe) static var title: LocalizedStringResource = "Show Answer"
    nonisolated(unsafe) static var openAppWhenRun: Bool = false

    @Parameter(title: "Card ID")
    var cardID: String

    func perform() async throws -> some IntentResult {
        guard let uuid = UUID(uuidString: cardID) else {
            log.error("Dropped reveal: unparseable cardID (cardID=\(cardID, privacy: .public))")
            return .result()
        }
        let containerURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: InboxConstants.appGroupID)
            ?? FileManager.default.temporaryDirectory
        let bridge = WidgetBridge(containerURL: containerURL)

        // Stale-tap guard: only reveal if the snapshot still shows this card
        // as current. If the widget already advanced past it, no-op.
        guard let revealed = WidgetDueSnapshot.revealing(current: bridge.readSnapshot(), cardID: uuid) else {
            return .result()
        }

        do {
            try bridge.writeSnapshot(revealed)
        } catch {
            log.error("widget reveal write failed: \(error.localizedDescription, privacy: .public)")
            return .result()
        }

        WidgetCenter.shared.reloadTimelines(ofKind: AnghkooeyReviewWidget.kind)
        return .result()
    }
}
