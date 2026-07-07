import Testing
import Foundation
@testable import AnghkooeyUI
import AnghkooeyCore

/// Regression coverage for #19: `ReviewSession` used to capture the
/// `FSRS6Engine` it was constructed with as a `let`, so a later swap of
/// `AppState.scheduler` (e.g. after "Optimize my schedule" resolves new
/// FSRS-6 params) never reached an in-flight review session. The fix
/// replaces the stored engine with a provider closure `() -> any FSRS6Engine`
/// so every call site re-reads the *current* engine.
@Suite("ReviewSession — #19 scheduler closure")
@MainActor
struct ReviewSessionSchedulerClosureTests {

    private func seedOneDueCard(in store: MockCardStore, now: Date) async throws {
        _ = try await store.create(
            question: "Q",
            answer: "A",
            sourceSpan: nil,
            now: now
        )
    }

    @Test("submit(grade:) reads the scheduler at call time, not at construction time")
    func submitReadsCurrentSchedulerAtCallTime() async throws {
        let now = Date(timeIntervalSinceReferenceDate: 0)
        let store = MockCardStore()
        try await seedOneDueCard(in: store, now: now)

        let spyA = SpyFSRS6Engine(dueOffset: 86_400)
        let spyB = SpyFSRS6Engine(dueOffset: 4 * 86_400)
        var current: any FSRS6Engine = spyA

        let session = ReviewSession(
            store: store,
            scheduler: { current },
            clock: { now }
        )
        await session.loadDueQueue()

        // Swap the live engine *after* the session was built — this is exactly
        // what AppState.refreshScheduler() does mid-app-lifetime.
        current = spyB

        session.revealAnswer()
        await session.submit(grade: .good)

        #expect(spyB.nextCallCount == 1)
        #expect(spyA.nextCallCount == 0)
    }

    @Test("currentIntervals reflects the current scheduler after a swap")
    func currentIntervalsReflectsSwappedScheduler() async throws {
        let now = Date(timeIntervalSinceReferenceDate: 0)
        let store = MockCardStore()
        try await seedOneDueCard(in: store, now: now)

        let spyAOffset: TimeInterval = 86_400
        let spyBOffset: TimeInterval = 4 * 86_400
        let spyA = SpyFSRS6Engine(dueOffset: spyAOffset)
        let spyB = SpyFSRS6Engine(dueOffset: spyBOffset)
        var current: any FSRS6Engine = spyA

        let session = ReviewSession(
            store: store,
            scheduler: { current },
            clock: { now }
        )
        await session.loadDueQueue()

        let beforeSwap = session.currentIntervals[.good]
        #expect(beforeSwap == spyAOffset)

        current = spyB
        let afterSwap = session.currentIntervals[.good]
        #expect(afterSwap == spyBOffset)
    }
}

/// Spy `FSRS6Engine` that records how many times `next(...)` was called and
/// returns a distinguishable projected due date (`now + dueOffset`) so tests
/// can tell two spy instances apart via `currentIntervals`.
final class SpyFSRS6Engine: FSRS6Engine, @unchecked Sendable {
    public let parameters: FSRSParameters = .default
    private(set) var nextCallCount = 0
    private let dueOffset: TimeInterval

    init(dueOffset: TimeInterval) {
        self.dueOffset = dueOffset
    }

    func next(card: SchedulingCard, rating: Rating, now: Date) throws -> SchedulerOutput {
        nextCallCount += 1
        var newCard = card
        newCard.reps += 1
        newCard.lastReview = now
        newCard.due = now.addingTimeInterval(dueOffset)
        let log = ReviewLogEntry(
            rating: rating,
            stateBefore: card.state,
            stabilityBefore: card.stability,
            difficultyBefore: card.difficulty,
            elapsedDays: 0,
            scheduledDays: card.scheduledDays,
            reviewedAt: now
        )
        return SchedulerOutput(card: newCard, log: log)
    }
}
