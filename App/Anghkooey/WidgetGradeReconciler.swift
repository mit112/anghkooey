import Foundation
import AnghkooeyCore

/// Replays widget grade decisions into the store on app foreground.
///
/// Idempotent within a session: `appliedIDs` tracks decisions already
/// processed so replaying the same `grades.jsonl` twice (e.g. on rapid
/// foreground/background cycles) only applies each decision once.
///
/// Cross-relaunch note: `appliedIDs` is in-memory only. On a fresh launch the
/// file is read once and each decision is applied exactly once before the file
/// is cleared — that's the normal path. The crash window (app crashes between
/// `apply` and `clearGrades`) is accepted per ADR-0010: replaying one extra
/// review has negligible FSRS impact.
@MainActor
final class WidgetGradeReconciler {

    private let store: any CardStoreProtocol
    private let bridge: WidgetBridge
    private let scheduler: any FSRS6Engine
    private var appliedIDs: Set<UUID> = []

    init(
        store: any CardStoreProtocol,
        bridge: WidgetBridge,
        scheduler: any FSRS6Engine = LiveFSRS6Engine()
    ) {
        self.store = store
        self.bridge = bridge
        self.scheduler = scheduler
    }

    /// Applies any pending widget grades to the store, then rewrites the
    /// due-card snapshot so the widget shows fresh data.
    func reconcile(now: Date = .now) async throws {
        let decisions = bridge.readGrades().sorted { $0.decidedAt < $1.decidedAt }
        guard !decisions.isEmpty else { return }

        let allCards = try await store.allCards()
        let cardsByID = Dictionary(uniqueKeysWithValues: allCards.map { ($0.id, $0) })

        for decision in decisions {
            guard !appliedIDs.contains(decision.id) else { continue }
            appliedIDs.insert(decision.id)

            guard let card = cardsByID[decision.cardID] else {
                // Unknown card — drop silently.
                continue
            }

            do {
                let output = try scheduler.next(
                    card: card.schedulingCard,
                    rating: decision.rating,
                    now: decision.decidedAt
                )
                try await store.apply(output, to: card.id, grade: decision.rating, now: decision.decidedAt)
            } catch {
                // Non-fatal: log and continue so remaining decisions are processed.
                // A future telemetry hook can capture `error` here.
                _ = error
            }
        }

        try bridge.clearGrades()
        try await rewriteSnapshot(now: now)
    }

    /// Rewrites the widget's due-card snapshot to reflect the current store state.
    /// Call this after any card is accepted or reviewed in-app, too.
    func rewriteSnapshot(now: Date = .now) async throws {
        let due = try await store.dueCards(asOf: now)
        if let first = due.first {
            try bridge.writeSnapshot(
                WidgetDueSnapshot(cardID: first.id, question: first.question, dueCount: due.count)
            )
        } else {
            try bridge.clearSnapshot()
        }
    }
}
