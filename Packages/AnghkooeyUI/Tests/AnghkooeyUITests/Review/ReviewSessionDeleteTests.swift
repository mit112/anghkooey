import Testing
import Foundation
@testable import AnghkooeyUI
import AnghkooeyCore

/// Coverage for `ReviewSession.deleteCurrentCard(cardID:)` and
/// `handleExternalDelete(cardID:)` (#38). A delete is a correction, not a
/// review — it must never touch `summary`, and it must guard against acting
/// on a stale identity the same way `submitEdit` does.
@Suite("ReviewSession — #38 card deletion")
@MainActor
struct ReviewSessionDeleteTests {

    private func makeSession(
        store: MockCardStore = MockCardStore(),
        now: Date = Date(timeIntervalSinceReferenceDate: 0)
    ) -> ReviewSession {
        ReviewSession(
            store: store,
            scheduler: { MockFSRS6Engine() },
            clock: { now }
        )
    }

    @discardableResult
    private func seedCards(
        count: Int,
        in store: MockCardStore,
        now: Date = Date(timeIntervalSinceReferenceDate: 0)
    ) async throws -> [Card.Snapshot] {
        var cards: [Card.Snapshot] = []
        for index in 1...count {
            cards.append(try await store.create(
                question: "Q\(index)",
                answer: "A\(index)",
                sourceSpan: nil,
                now: now
            ))
        }
        return cards
    }

    // MARK: - deleteCurrentCard

    @Test("deleteCurrentCard advances to the next queued card without incrementing summary.reviewed")
    func deleteCurrentCardAdvancesWithoutRecordingSummary() async throws {
        let now = Date(timeIntervalSinceReferenceDate: 0)
        let store = MockCardStore()
        try await seedCards(count: 2, in: store, now: now)
        let session = makeSession(store: store, now: now)
        await session.loadDueQueue()
        let firstID = try #require(session.currentCard?.id)
        #expect(session.queueRemaining == 1)

        try await session.deleteCurrentCard(cardID: firstID)

        #expect(session.currentCard?.id != firstID)
        #expect(session.currentCard != nil)
        #expect(session.queueRemaining == 0)
        #expect(session.summary.reviewed == 0)
    }

    @Test("deleteCurrentCard removes the card from the store")
    func deleteCurrentCardRemovesFromStore() async throws {
        let now = Date(timeIntervalSinceReferenceDate: 0)
        let store = MockCardStore()
        try await seedCards(count: 2, in: store, now: now)
        let session = makeSession(store: store, now: now)
        await session.loadDueQueue()
        let firstID = try #require(session.currentCard?.id)

        try await session.deleteCurrentCard(cardID: firstID)

        #expect(!store.cards.contains { $0.id == firstID })
    }

    @Test("deleteCurrentCard on the last card transitions to .empty")
    func deleteCurrentCardOnLastCardTransitionsToEmpty() async throws {
        let now = Date(timeIntervalSinceReferenceDate: 0)
        let store = MockCardStore()
        try await seedCards(count: 1, in: store, now: now)
        let session = makeSession(store: store, now: now)
        await session.loadDueQueue()
        let cardID = try #require(session.currentCard?.id)

        try await session.deleteCurrentCard(cardID: cardID)

        #expect(session.state == .empty)
        #expect(session.currentCard == nil)
        #expect(session.summary.reviewed == 0)
    }

    @Test("deleteCurrentCard throws .noCurrentCard when there is no current card")
    func deleteCurrentCardThrowsNoCurrentCardWhenEmpty() async throws {
        let now = Date(timeIntervalSinceReferenceDate: 0)
        let store = MockCardStore()
        let session = makeSession(store: store, now: now)
        await session.loadDueQueue() // no cards; state == .empty, currentCard == nil

        await #expect(throws: ReviewSessionError.noCurrentCard) {
            try await session.deleteCurrentCard(cardID: UUID())
        }
    }

    @Test("deleteCurrentCard throws .cardChanged when cardID does not match currentCard and does not touch the store")
    func deleteCurrentCardThrowsCardChangedAndLeavesStoreUntouched() async throws {
        let now = Date(timeIntervalSinceReferenceDate: 0)
        let store = MockCardStore()
        try await seedCards(count: 2, in: store, now: now)
        let session = makeSession(store: store, now: now)
        await session.loadDueQueue()
        let currentID = try #require(session.currentCard?.id)
        let staleID = UUID() // definitely not the current card

        await #expect(throws: ReviewSessionError.cardChanged) {
            try await session.deleteCurrentCard(cardID: staleID)
        }

        // State untouched: the real current card is still there and the
        // store was never asked to delete anything.
        #expect(session.currentCard?.id == currentID)
        #expect(store.cards.count == 2)
    }

    @Test("deleteCurrentCard rethrows a store failure and leaves currentCard unchanged")
    func deleteCurrentCardRethrowsStoreFailure() async throws {
        let now = Date(timeIntervalSinceReferenceDate: 0)
        let store = MockCardStore()
        try await seedCards(count: 2, in: store, now: now)
        store.deleteError = PersistenceError.invalidShift(days: -1)
        let session = makeSession(store: store, now: now)
        await session.loadDueQueue()
        let cardID = try #require(session.currentCard?.id)

        await #expect(throws: (any Error).self) {
            try await session.deleteCurrentCard(cardID: cardID)
        }

        #expect(session.currentCard?.id == cardID)
        #expect(store.cards.contains { $0.id == cardID })
    }

    // MARK: - handleExternalDelete

    @Test("handleExternalDelete removes a queued (non-current) id and decrements queueRemaining")
    func handleExternalDeleteRemovesQueuedCard() async throws {
        let now = Date(timeIntervalSinceReferenceDate: 0)
        let store = MockCardStore()
        try await seedCards(count: 3, in: store, now: now)
        let session = makeSession(store: store, now: now)
        await session.loadDueQueue()
        let currentID = try #require(session.currentCard?.id)
        #expect(session.queueRemaining == 2)

        // Find an id that's queued but not current, by grabbing a due-card id
        // from the store that isn't the current one.
        let allDue = try await store.dueCards(asOf: now)
        let queuedID = try #require(allDue.map(\.id).first { $0 != currentID })

        session.handleExternalDelete(cardID: queuedID)

        #expect(session.queueRemaining == 1)
        #expect(session.currentCard?.id == currentID) // current card untouched
    }

    @Test("handleExternalDelete is a no-op for an id not present in the queue or current card")
    func handleExternalDeleteNoOpForAbsentID() async throws {
        let now = Date(timeIntervalSinceReferenceDate: 0)
        let store = MockCardStore()
        try await seedCards(count: 2, in: store, now: now)
        let session = makeSession(store: store, now: now)
        await session.loadDueQueue()
        let currentID = try #require(session.currentCard?.id)
        let remainingBefore = session.queueRemaining

        session.handleExternalDelete(cardID: UUID())

        #expect(session.queueRemaining == remainingBefore)
        #expect(session.currentCard?.id == currentID)
    }

    @Test("handleExternalDelete on the (defensively) current card advances to the next queued card synchronously")
    func handleExternalDeleteOnCurrentCardAdvancesSynchronously() async throws {
        let now = Date(timeIntervalSinceReferenceDate: 0)
        let store = MockCardStore()
        try await seedCards(count: 2, in: store, now: now)
        let session = makeSession(store: store, now: now)
        await session.loadDueQueue()
        let currentID = try #require(session.currentCard?.id)

        session.handleExternalDelete(cardID: currentID)

        #expect(session.currentCard?.id != currentID)
        #expect(session.currentCard != nil)
        #expect(session.queueRemaining == 0)
    }

    @Test("handleExternalDelete on the current card with an empty queue sets state to .empty synchronously")
    func handleExternalDeleteOnCurrentCardWithEmptyQueueSetsEmptyState() async throws {
        let now = Date(timeIntervalSinceReferenceDate: 0)
        let store = MockCardStore()
        try await seedCards(count: 1, in: store, now: now)
        let session = makeSession(store: store, now: now)
        await session.loadDueQueue()
        let currentID = try #require(session.currentCard?.id)

        session.handleExternalDelete(cardID: currentID)

        #expect(session.currentCard == nil)
        #expect(session.queueRemaining == 0)
        #expect(session.state == .empty)
    }

    // NOTE: the generation-race path (a concurrent `loadDueQueue()` superseding
    // an in-flight `deleteCurrentCard`, and the requirement that the delete
    // STILL posts `.anghkooeyDeckDidChange` without clobbering the reload's
    // state) is covered by `ReviewSessionAwaitGuardTests`'s "Bug 4 (#38)" test,
    // which uses `MockCardStore.deleteGate` + a clock-driven concurrent reload.
}
