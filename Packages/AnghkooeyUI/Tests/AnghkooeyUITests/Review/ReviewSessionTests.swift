import Testing
import Foundation
@testable import AnghkooeyUI
import AnghkooeyCore

@Suite("ReviewSession — M4.7 contract")
@MainActor
struct ReviewSessionTests {
    private func makeSession(
        store: MockCardStore = MockCardStore(),
        now: Date = Date(timeIntervalSinceReferenceDate: 0)
    ) -> ReviewSession {
        ReviewSession(
            store: store,
            scheduler: MockFSRS6Engine(),
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
            let card = try await store.create(
                question: "Q\(index)",
                answer: "A\(index)",
                sourceSpan: nil,
                now: now
            )
            cards.append(card)
        }
        return cards
    }

    private func makeLoadedSession(
        cardCount: Int = 2,
        now: Date = Date(timeIntervalSinceReferenceDate: 0)
    ) async throws -> (session: ReviewSession, store: MockCardStore) {
        let store = MockCardStore()
        try await seedCards(count: cardCount, in: store, now: now)
        let session = makeSession(store: store, now: now)
        await session.loadDueQueue()
        return (session, store)
    }

    @Test("loadDueQueue populates currentCard and queueRemaining == 1 for two cards")
    func loadDueQueuePopulatesCurrentCardAndQueueRemaining() async throws {
        let (session, _) = try await makeLoadedSession(cardCount: 2)

        #expect(session.currentCard != nil)
        #expect(session.queueRemaining == 1)
    }

    @Test("submit(.good) sends .good to the scheduler and advances to the next card")
    func submitGoodSendsGoodRatingAndAdvances() async throws {
        let (session, store) = try await makeLoadedSession(cardCount: 2)
        let firstID = try #require(session.currentCard?.id)

        session.revealAnswer()
        await session.submit(grade: .good)

        let appliedRating = try #require(store.reviewLogs.first?.output.log.rating)
        #expect(appliedRating == .good)
        #expect(session.currentCard?.id != firstID)
    }

    @Test("submit(.again) sends .again to the scheduler")
    func submitAgainSendsAgainRating() async throws {
        let (session, store) = try await makeLoadedSession(cardCount: 2)

        session.revealAnswer()
        await session.submit(grade: .again)

        let appliedRating = try #require(store.reviewLogs.first?.output.log.rating)
        #expect(appliedRating == .again)
    }

    @Test("submit(.hard) sends .hard to the scheduler")
    func submitHardSendsHardRating() async throws {
        let (session, store) = try await makeLoadedSession(cardCount: 2)

        session.revealAnswer()
        await session.submit(grade: .hard)

        let appliedRating = try #require(store.reviewLogs.first?.output.log.rating)
        #expect(appliedRating == .hard)
    }

    @Test("submit(.easy) sends .easy to the scheduler")
    func submitEasySendsEasyRating() async throws {
        let (session, store) = try await makeLoadedSession(cardCount: 2)

        session.revealAnswer()
        await session.submit(grade: .easy)

        let appliedRating = try #require(store.reviewLogs.first?.output.log.rating)
        #expect(appliedRating == .easy)
    }

    @Test("submit on the last card transitions state to .empty and clears currentCard")
    func submitOnLastCardTransitionsToEmpty() async throws {
        let (session, _) = try await makeLoadedSession(cardCount: 1)

        session.revealAnswer()
        await session.submit(grade: .good)

        #expect(session.state == .empty)
        #expect(session.currentCard == nil)
    }

    @Test("revealAnswer is idempotent")
    func revealAnswerIsIdempotent() async throws {
        let (session, _) = try await makeLoadedSession(cardCount: 1)

        #expect(session.isAnswerRevealed == false)
        session.revealAnswer()
        #expect(session.isAnswerRevealed == true)
        session.revealAnswer()
        #expect(session.isAnswerRevealed == true)
    }

    @Test("loadDueQueue sets totalCardCount to the store total, not the due count, while reviewing")
    func loadDueQueueSetsTotalCardCountToStoreTotalWhileReviewing() async throws {
        let now = Date(timeIntervalSinceReferenceDate: 0)
        let notYetDue = now.addingTimeInterval(86_400)
        let store = MockCardStore()
        for index in 1...3 {
            _ = try await store.create(question: "Due\(index)", answer: "A\(index)", sourceSpan: nil, now: now)
        }
        for index in 1...2 {
            _ = try await store.create(question: "NotDue\(index)", answer: "A\(index)", sourceSpan: nil, now: notYetDue)
        }

        let session = makeSession(store: store, now: now)
        await session.loadDueQueue()

        #expect(session.state == .reviewing)
        #expect(session.totalCardCount == 5)
    }

    @Test("loadDueQueue surfaces a count() failure as .error rather than swallowing it into .empty")
    func loadDueQueuePropagatesCountFailureAsError() async throws {
        let now = Date(timeIntervalSinceReferenceDate: 0)
        let store = MockCardStore()
        store.countError = PersistenceError.invalidShift(days: -1)

        let session = makeSession(store: store, now: now)
        await session.loadDueQueue()

        guard case .error = session.state else {
            Issue.record("Expected .error state, got \(session.state)")
            return
        }
        #expect(session.totalCardCount == 0)
    }
}
