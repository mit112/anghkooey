import Testing
import Foundation
import AnghkooeyCore
@testable import AnghkooeyUI

@Suite("ReviewSession — Cushion Mode")
@MainActor
struct ReviewSessionCushionTests {

    @Test("under backlog threshold: shows all due cards, no cushion")
    func underThreshold_showsAllDue() async {
        let store = MockCardStore()
        try? await seedDueCards(in: store, count: 30)
        let session = ReviewSession(
            store: store,
            scheduler: { FakeNoopScheduler() },
            clock: { .now },
            dailyBatchCap: 20,
            backlogThreshold: 50
        )
        await session.loadDueQueue()
        #expect(session.queueRemaining == 29)   // 30 due, currentCard pops 1
        #expect(session.backlogTotal == 30)
        #expect(session.isCushionActive == false)
    }

    @Test("over backlog threshold: caps visible queue to dailyBatchCap")
    func overThreshold_capsBatch() async {
        let store = MockCardStore()
        try? await seedDueCards(in: store, count: 87)
        let session = ReviewSession(
            store: store,
            scheduler: { FakeNoopScheduler() },
            clock: { .now },
            dailyBatchCap: 20,
            backlogThreshold: 50
        )
        await session.loadDueQueue()
        #expect(session.queueRemaining == 19)   // 20 batch cap, currentCard pops 1
        #expect(session.backlogTotal == 87)
        #expect(session.isCushionActive == true)
    }

    @Test("at exact threshold: no cushion (boundary)")
    func atThreshold_noCushion() async {
        let store = MockCardStore()
        try? await seedDueCards(in: store, count: 50)
        let session = ReviewSession(
            store: store,
            scheduler: { FakeNoopScheduler() },
            clock: { .now },
            dailyBatchCap: 20,
            backlogThreshold: 50
        )
        await session.loadDueQueue()
        #expect(session.queueRemaining == 49)
        #expect(session.isCushionActive == false)
    }
}

private func seedDueCards(in store: MockCardStore, count: Int) async throws {
    let pastDate = Date.now.addingTimeInterval(-3600)
    for i in 0..<count {
        try await store.create(
            question: "q\(i)",
            answer: "a\(i)",
            sourceSpan: nil,
            now: pastDate
        )
    }
}

private struct FakeNoopScheduler: FSRS6Engine {
    var parameters: FSRSParameters { .default }
    func next(card: SchedulingCard, rating: Rating, now: Date) throws -> SchedulerOutput {
        throw SchedulingError.reviewedBeforeLastReview
    }
}
