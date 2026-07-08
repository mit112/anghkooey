import Testing
import Foundation
@testable import Anghkooey
@testable import AnghkooeyCore

@Suite("Widget grade reconciliation")
@MainActor
struct GradeReconciliationTests {

    private func tmpDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("a queued grade is applied to the store and the queue is cleared")
    func appliesAndClears() async throws {
        let dir = try tmpDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = MockCardStore()
        let card = try await store.create(question: "q", answer: "a", sourceSpan: nil, tags: [], now: .now)
        let bridge = WidgetBridge(containerURL: dir)
        try bridge.appendGrade(WidgetGradeDecision(id: UUID(), cardID: card.id, rating: .good, decidedAt: .now))

        let reconciler = WidgetGradeReconciler(store: store, bridge: bridge)
        try await reconciler.reconcile(now: .now)

        #expect(store.reviewLogs.count == 1)
        #expect(store.reviewLogs[0].cardID == card.id)
        #expect(bridge.readGrades().isEmpty)
    }

    @Test("replaying the same decision id twice applies it only once (idempotent)")
    func idempotentReplay() async throws {
        let dir = try tmpDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = MockCardStore()
        let card = try await store.create(question: "q", answer: "a", sourceSpan: nil, tags: [], now: .now)
        let bridge = WidgetBridge(containerURL: dir)
        let decision = WidgetGradeDecision(id: UUID(), cardID: card.id, rating: .good, decidedAt: .now)
        try bridge.appendGrade(decision)
        try bridge.appendGrade(decision) // duplicate

        let reconciler = WidgetGradeReconciler(store: store, bridge: bridge)
        try await reconciler.reconcile(now: .now)

        #expect(store.reviewLogs.count == 1)
    }

    @Test("a grade for an unknown card is dropped without error")
    func unknownCardDropped() async throws {
        let dir = try tmpDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = MockCardStore()
        let bridge = WidgetBridge(containerURL: dir)
        try bridge.appendGrade(
            WidgetGradeDecision(id: UUID(), cardID: UUID(), rating: .again, decidedAt: .now)
        )
        let reconciler = WidgetGradeReconciler(store: store, bridge: bridge)
        try await reconciler.reconcile(now: .now)
        #expect(store.reviewLogs.isEmpty)
        #expect(bridge.readGrades().isEmpty)
    }

    // MARK: - Epic #9 checkpoint: apply failures must not lose the grade

    /// Distinguishable failure used to simulate a scheduler/store error
    /// without depending on any particular concrete error type.
    private enum SimulatedFailure: Error, Sendable {
        case boom
    }

    /// Mutable box so a test can flip the failure off between two
    /// `reconcile()` calls on the SAME reconciler instance — the scheduler
    /// is fixed at `WidgetGradeReconciler.init`, so this is the only way to
    /// simulate "the transient failure clears by the next retry" without a
    /// second reconciler (which would lose `appliedIDs` state).
    private final class FailingRatingBox: @unchecked Sendable {
        var failingRating: Rating?
        init(failingRating: Rating?) { self.failingRating = failingRating }
    }

    /// Deterministic ``FSRS6Engine`` that fails only for `box.failingRating`,
    /// so a test can make exactly one decision in a batch fail while the
    /// rest succeed via the real ``MockFSRS6Engine`` transition table.
    private struct FailingRatingScheduler: FSRS6Engine {
        let box: FailingRatingBox
        var parameters: FSRSParameters { MockFSRS6Engine().parameters }
        func next(card: SchedulingCard, rating: Rating, now: Date) throws -> SchedulerOutput {
            guard rating != box.failingRating else { throw SimulatedFailure.boom }
            return try MockFSRS6Engine().next(card: card, rating: rating, now: now)
        }
    }

    @Test("an apply failure does not lose the grade: the file is retained and the decision is retried on the next reconcile")
    func applyFailureRetainsGradeForRetry() async throws {
        let dir = try tmpDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = MockCardStore()
        let card = try await store.create(question: "q", answer: "a", sourceSpan: nil, tags: [], now: .now)
        let bridge = WidgetBridge(containerURL: dir)
        let decision = WidgetGradeDecision(id: UUID(), cardID: card.id, rating: .good, decidedAt: .now)
        try bridge.appendGrade(decision)

        store.applyError = SimulatedFailure.boom
        let reconciler = WidgetGradeReconciler(store: store, bridge: bridge)
        try await reconciler.reconcile(now: .now)

        // No data loss: nothing applied, and the decision is still on disk.
        #expect(store.reviewLogs.isEmpty)
        let afterFirstAttempt = bridge.readGrades()
        #expect(afterFirstAttempt.count == 1)
        #expect(afterFirstAttempt.first?.id == decision.id)

        // Same-session retry (e.g. next drain pass): once the transient
        // failure clears, the previously-failed decision (never marked
        // applied) succeeds and the file is finally cleared.
        store.applyError = nil
        try await reconciler.reconcile(now: .now)

        #expect(store.reviewLogs.count == 1)
        #expect(store.reviewLogs[0].cardID == card.id)
        #expect(bridge.readGrades().isEmpty)
    }

    @Test("a mixed batch applies the good decision and retains the failing one for retry")
    func mixedBatchAppliesGoodAndRetainsFailingForRetry() async throws {
        let dir = try tmpDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = MockCardStore()
        let goodCard = try await store.create(question: "q1", answer: "a1", sourceSpan: nil, tags: [], now: .now)
        let badCard = try await store.create(question: "q2", answer: "a2", sourceSpan: nil, tags: [], now: .now)
        let bridge = WidgetBridge(containerURL: dir)
        let goodDecision = WidgetGradeDecision(id: UUID(), cardID: goodCard.id, rating: .good, decidedAt: .now)
        let badDecision = WidgetGradeDecision(
            id: UUID(), cardID: badCard.id, rating: .hard, decidedAt: .now.addingTimeInterval(1)
        )
        try bridge.appendGrade(goodDecision)
        try bridge.appendGrade(badDecision)

        let box = FailingRatingBox(failingRating: .hard)
        let scheduler = FailingRatingScheduler(box: box)
        let reconciler = WidgetGradeReconciler(store: store, bridge: bridge, scheduler: scheduler)
        try await reconciler.reconcile(now: .now)

        // The good decision applied...
        #expect(store.reviewLogs.count == 1)
        #expect(store.reviewLogs[0].cardID == goodCard.id)
        // ...but since there's no subset-write API, a retryable failure
        // anywhere in the batch keeps the WHOLE file intact (including the
        // already-applied good decision) rather than partially rewriting it.
        #expect(bridge.readGrades().count == 2)

        // Retry (e.g. next drain pass) with the transient failure cleared:
        // the good decision is skipped via `appliedIDs` (not double-applied)
        // and the previously-failing one now succeeds, clearing the file.
        box.failingRating = nil
        try await reconciler.reconcile(now: .now)

        #expect(store.reviewLogs.count == 2)
        #expect(Set(store.reviewLogs.map(\.cardID)) == [goodCard.id, badCard.id])
        #expect(bridge.readGrades().isEmpty)
    }

    @Test("a successful batch still clears the file (existing behavior preserved)")
    func successfulBatchStillClears() async throws {
        let dir = try tmpDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = MockCardStore()
        let card = try await store.create(question: "q", answer: "a", sourceSpan: nil, tags: [], now: .now)
        let bridge = WidgetBridge(containerURL: dir)
        try bridge.appendGrade(WidgetGradeDecision(id: UUID(), cardID: card.id, rating: .good, decidedAt: .now))

        let reconciler = WidgetGradeReconciler(store: store, bridge: bridge)
        try await reconciler.reconcile(now: .now)

        #expect(store.reviewLogs.count == 1)
        #expect(bridge.readGrades().isEmpty)
    }

    // MARK: - Issue #35/#36: widget grade-advance + answer-reveal

    @Test("rewriteSnapshot writes the current card's answer and a bounded (max 5) queue of upcoming due cards")
    func rewriteSnapshotWritesAnswerAndBoundedQueue() async throws {
        let dir = try tmpDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = MockCardStore()
        let base = Date(timeIntervalSinceReferenceDate: 0)
        var created: [Card.Snapshot] = []
        for i in 0..<8 {
            let card = try await store.create(
                question: "q\(i)", answer: "a\(i)", sourceSpan: nil, tags: [],
                now: base.addingTimeInterval(Double(i))
            )
            created.append(card)
        }
        let bridge = WidgetBridge(containerURL: dir)
        let reconciler = WidgetGradeReconciler(store: store, bridge: bridge)

        try await reconciler.rewriteSnapshot(now: base.addingTimeInterval(100))

        let snap = try #require(bridge.readSnapshot())
        #expect(snap.cardID == created[0].id)
        #expect(snap.question == created[0].question)
        #expect(snap.answer == created[0].answer)
        #expect(snap.revealed == false)
        #expect(snap.dueCount == 8)
        let queue = try #require(snap.queue)
        #expect(queue.count == 5)
        #expect(queue.map(\.cardID) == created[1...5].map(\.id))
        #expect(queue.map(\.question) == created[1...5].map(\.question))
        #expect(queue.map(\.answer) == created[1...5].map(\.answer))
    }

    @Test("rewriteSnapshot with a single due card writes an empty queue")
    func rewriteSnapshotSingleCardEmptyQueue() async throws {
        let dir = try tmpDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = MockCardStore()
        let card = try await store.create(question: "q", answer: "a", sourceSpan: nil, tags: [], now: .now)
        let bridge = WidgetBridge(containerURL: dir)
        let reconciler = WidgetGradeReconciler(store: store, bridge: bridge)

        try await reconciler.rewriteSnapshot(now: .now)

        let snap = try #require(bridge.readSnapshot())
        #expect(snap.cardID == card.id)
        #expect(snap.answer == card.answer)
        #expect(snap.dueCount == 1)
        #expect(snap.queue?.isEmpty == true)
    }

    @Test("reconciling two decisions (current + queued-next, simulating a widget local advance) matches grading both in-app directly, applied once and in order")
    func widgetAdvanceParityWithInAppGrading() async throws {
        let dir = try tmpDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let t0 = Date(timeIntervalSinceReferenceDate: 0)

        // Two independently-seeded stores with the same two cards.
        let widgetStore = MockCardStore()
        let inAppStore = MockCardStore()
        let widgetA = try await widgetStore.create(question: "qA", answer: "aA", sourceSpan: nil, tags: [], now: t0)
        let widgetB = try await widgetStore.create(
            question: "qB", answer: "aB", sourceSpan: nil, tags: [], now: t0.addingTimeInterval(1)
        )
        let inAppA = try await inAppStore.create(question: "qA", answer: "aA", sourceSpan: nil, tags: [], now: t0)
        let inAppB = try await inAppStore.create(
            question: "qB", answer: "aB", sourceSpan: nil, tags: [], now: t0.addingTimeInterval(1)
        )

        let decidedA = t0.addingTimeInterval(10)
        let decidedB = t0.addingTimeInterval(20)

        // Widget side: simulate two taps — grade the current card (A), then
        // grade the locally-advanced next card (B) — exactly as
        // `GradeCardIntent` would append them, without any store access.
        let bridge = WidgetBridge(containerURL: dir)
        try bridge.appendGrade(WidgetGradeDecision(id: UUID(), cardID: widgetA.id, rating: .good, decidedAt: decidedA))
        try bridge.appendGrade(WidgetGradeDecision(id: UUID(), cardID: widgetB.id, rating: .good, decidedAt: decidedB))

        // Same scheduler instance for both paths — `WidgetGradeReconciler`
        // defaults to `LiveFSRS6Engine()`, which would make the "control"
        // comparison meaningless if the two paths used different engines.
        let scheduler = MockFSRS6Engine()
        let reconciler = WidgetGradeReconciler(store: widgetStore, bridge: bridge, scheduler: scheduler)
        try await reconciler.reconcile(now: decidedB)

        // In-app control: grade the same two cards directly, in the same
        // order, via the same scheduler.
        let outputA = try scheduler.next(card: inAppA.schedulingCard, rating: .good, now: decidedA)
        try await inAppStore.apply(outputA, to: inAppA.id, grade: .good, now: decidedA)
        let inAppBBeforeSecondGrade = try #require(inAppStore.cards.first { $0.id == inAppB.id })
        let outputB = try scheduler.next(card: inAppBBeforeSecondGrade.schedulingCard, rating: .good, now: decidedB)
        try await inAppStore.apply(outputB, to: inAppB.id, grade: .good, now: decidedB)

        // Both decisions applied exactly once, in order.
        #expect(widgetStore.reviewLogs.count == 2)
        #expect(widgetStore.reviewLogs.map(\.cardID) == [widgetA.id, widgetB.id])
        #expect(bridge.readGrades().isEmpty)

        // Reconciled (widget-path) state matches the in-app-graded control.
        let reconciledA = try #require(widgetStore.cards.first { $0.id == widgetA.id })
        let reconciledB = try #require(widgetStore.cards.first { $0.id == widgetB.id })
        let controlA = try #require(inAppStore.cards.first { $0.id == inAppA.id })
        let controlB = try #require(inAppStore.cards.first { $0.id == inAppB.id })

        #expect(reconciledA.stability == controlA.stability)
        #expect(reconciledA.difficulty == controlA.difficulty)
        #expect(reconciledA.dueAt == controlA.dueAt)
        #expect(reconciledA.state == controlA.state)
        #expect(reconciledB.stability == controlB.stability)
        #expect(reconciledB.difficulty == controlB.difficulty)
        #expect(reconciledB.dueAt == controlB.dueAt)
        #expect(reconciledB.state == controlB.state)
    }
}
