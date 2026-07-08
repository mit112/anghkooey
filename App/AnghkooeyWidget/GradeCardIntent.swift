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

        // Stale-tap guard: if the on-disk snapshot no longer shows this card
        // as current (e.g. a duplicate tap, or the app already reconciled
        // past it), the card already advanced — this tap must be a harmless
        // no-op. Do NOT append a grade decision and do NOT touch the snapshot.
        let current = bridge.readSnapshot()
        guard current?.cardID == uuid else {
            return .result()
        }

        // Append FIRST. If this throws, never advance the snapshot — a lost
        // grade decision is worse than a widget that looks momentarily stale
        // (the next `WidgetGradeReconciler.reconcile()` will just be a no-op).
        do {
            try bridge.appendGrade(WidgetGradeDecision(id: UUID(), cardID: uuid, rating: rating, decidedAt: .now))
        } catch {
            log.error("widget grade append failed: \(error.localizedDescription, privacy: .public)")
            return .result()
        }

        // Locally advance so the widget doesn't visibly freeze on the just-
        // graded card until the app relaunches and reconciles. The app is
        // authoritative — `WidgetGradeReconciler.rewriteSnapshot()`
        // overwrites this on its next pass, so no cross-process file lock is
        // needed here: at worst a lost write here is self-corrected there.
        //
        // The write is logged, not `try?`-swallowed: if it fails, the on-disk
        // snapshot still shows the just-graded card as current, so the next
        // tap would pass the stale-tap guard above and append a duplicate
        // grade — a log line is the only trace to diagnose that, and every
        // other failure branch in this intent logs too.
        do {
            switch WidgetDueSnapshot.advancing(from: current, gradedCardID: uuid) {
            case .staleTap:
                break
            case .allCaughtUp:
                try bridge.clearSnapshot()
            case .advanced(let next):
                try bridge.writeSnapshot(next)
            }
        } catch {
            log.error("widget snapshot advance failed: \(error.localizedDescription, privacy: .public)")
        }

        WidgetCenter.shared.reloadTimelines(ofKind: AnghkooeyReviewWidget.kind)
        return .result()
    }
}
