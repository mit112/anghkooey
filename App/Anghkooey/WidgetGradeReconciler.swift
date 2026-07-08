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

        // Tracks whether any decision hit a retryable (scheduler/store)
        // failure this pass. If so, `grades.jsonl` must NOT be cleared —
        // clearing it would permanently delete the user's still-unapplied
        // grade tap with no way to retry (the bug this guards against).
        var hadRetryableFailure = false

        for decision in decisions {
            guard !appliedIDs.contains(decision.id) else { continue }

            guard let card = cardsByID[decision.cardID] else {
                // Unknown card (e.g. deleted) — permanently undeliverable,
                // not retryable, so mark resolved and drop silently.
                appliedIDs.insert(decision.id)
                continue
            }

            do {
                let output = try scheduler.next(
                    card: card.schedulingCard,
                    rating: decision.rating,
                    now: decision.decidedAt
                )
                try await store.apply(output, to: card.id, grade: decision.rating, now: decision.decidedAt)
                // Only mark applied on success — a thrown apply must not be
                // skipped as "already applied" on a same-session retry.
                appliedIDs.insert(decision.id)
            } catch {
                CoreLog.persistence.error(
                    "widget grade decision \(decision.id) failed to apply: \(error.localizedDescription, privacy: .public)")
                hadRetryableFailure = true
            }
        }

        // Leave the file intact when a retryable failure occurred so the
        // failed decision(s) are retried on the next reconcile (this
        // session via `appliedIDs`, or on relaunch by re-reading the file).
        if !hadRetryableFailure {
            try bridge.clearGrades()
        }
        try await rewriteSnapshot(now: now)
    }

    /// Cap on `WidgetDueSnapshot.queue` length. Bounded so the widget's
    /// shared-container payload stays small; the app remains authoritative
    /// and rewrites this on every reconcile, so a small window is enough to
    /// cover a burst of local widget taps between app launches.
    private static let maxQueueLength = 5

    /// Rewrites the widget's due-card snapshot to reflect the current store
    /// state: the first due card (with its answer, unrevealed), plus a
    /// bounded queue of the next-up due cards so the widget can advance
    /// locally between rewrites. Call this after any card is accepted or
    /// reviewed in-app, too.
    func rewriteSnapshot(now: Date = .now) async throws {
        let due = try await store.dueCards(asOf: now)
        guard let first = due.first else {
            try bridge.clearSnapshot()
            return
        }
        let queue = due.dropFirst().prefix(Self.maxQueueLength).map {
            WidgetCardRef(cardID: $0.id, question: $0.question, answer: $0.answer)
        }
        try bridge.writeSnapshot(
            WidgetDueSnapshot(
                cardID: first.id,
                question: first.question,
                dueCount: due.count,
                answer: first.answer,
                revealed: false,
                queue: Array(queue)
            )
        )
    }
}
