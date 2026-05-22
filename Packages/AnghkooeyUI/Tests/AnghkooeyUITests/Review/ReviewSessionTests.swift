import Testing
import Foundation
@testable import AnghkooeyUI
import AnghkooeyCore

// MARK: - M4.7 contract tests
//
// These tests are RED until Codex replaces the fatalError stubs in
// ReviewSession with real implementations.

@Suite("ReviewSession — M4.7 contract")
@MainActor
struct ReviewSessionTests {

    // MARK: Helpers

    private func makeSession(cards: [Card.Snapshot] = [], applyError: Error? = nil) -> ReviewSession {
        let store = MockCardStore()
        // Seed the mock with cards that are due now
        for c in cards {
            Task { _ = try? await store.create(question: c.question, answer: c.answer, sourceSpan: c.sourceSpan, now: c.dueAt) }
        }
        return ReviewSession(
            store: store,
            scheduler: MockFSRS6Engine()
        )
    }

    private func makeSession(store: MockCardStore) -> ReviewSession {
        ReviewSession(store: store, scheduler: MockFSRS6Engine())
    }

    // MARK: loadDueQueue_populatesCurrent_andQueueRemaining

    @Test("loadDueQueue populates currentCard and sets queueRemaining")
    func loadDueQueue_populatesCurrent_andQueueRemaining() async throws {
        let store = MockCardStore()
        let now = Date()
        _ = try await store.create(question: "Q1", answer: "A1", sourceSpan: nil, now: now)
        _ = try await store.create(question: "Q2", answer: "A2", sourceSpan: nil, now: now)

        let session = makeSession(store: store)
        await session.loadDueQueue()

        #expect(session.currentCard != nil)
        #expect(session.queueRemaining == 1)   // 2 due, 1 is currentCard
        #expect(session.state == .reviewing)
    }

    // MARK: submit_gotIt_callsScheduler_withGoodRating_andAdvances

    @Test("submit(.gotIt) calls scheduler with .good rating and advances to next card")
    func submit_gotIt_callsScheduler_withGoodRating_andAdvances() async throws {
        let store = MockCardStore()
        let now = Date()
        _ = try await store.create(question: "Q1", answer: "A1", sourceSpan: nil, now: now)
        _ = try await store.create(question: "Q2", answer: "A2", sourceSpan: nil, now: now)

        let session = makeSession(store: store)
        await session.loadDueQueue()
        let firstID = try #require(session.currentCard?.id)

        session.revealAnswer()
        await session.submit(grade: .gotIt)

        let applied = store.reviewLogs.first
        let appliedRating = try #require(applied?.output.log.rating)
        #expect(appliedRating == .good)
        #expect(session.currentCard?.id != firstID)
    }

    // MARK: submit_missed_callsScheduler_withAgainRating_andAdvances

    @Test("submit(.missed) calls scheduler with .again rating and advances")
    func submit_missed_callsScheduler_withAgainRating_andAdvances() async throws {
        let store = MockCardStore()
        let now = Date()
        _ = try await store.create(question: "Q1", answer: "A1", sourceSpan: nil, now: now)
        _ = try await store.create(question: "Q2", answer: "A2", sourceSpan: nil, now: now)

        let session = makeSession(store: store)
        await session.loadDueQueue()

        session.revealAnswer()
        await session.submit(grade: .missed)

        let applied = store.reviewLogs.first
        let appliedRating = try #require(applied?.output.log.rating)
        #expect(appliedRating == .again)
    }

    // MARK: submit_onLastCard_movesToEmpty

    @Test("submit on the last card transitions state to .empty")
    func submit_onLastCard_movesToEmpty() async throws {
        let store = MockCardStore()
        let now = Date()
        _ = try await store.create(question: "Q1", answer: "A1", sourceSpan: nil, now: now)

        let session = makeSession(store: store)
        await session.loadDueQueue()

        session.revealAnswer()
        await session.submit(grade: .gotIt)

        #expect(session.state == .empty)
        #expect(session.currentCard == nil)
    }

    // MARK: revealAnswer_idempotent

    @Test("revealAnswer is idempotent — calling twice does not crash or double-toggle")
    func revealAnswer_idempotent() async throws {
        let store = MockCardStore()
        let now = Date()
        _ = try await store.create(question: "Q1", answer: "A1", sourceSpan: nil, now: now)

        let session = makeSession(store: store)
        await session.loadDueQueue()

        session.revealAnswer()
        session.revealAnswer()  // second call must not flip back

        #expect(session.isAnswerRevealed == true)
    }
}
