import Testing
import Foundation
import SwiftData
@testable import AnghkooeyCore

@Suite("CardStore.optimizationReviewLogs")
struct CardStoreOptimizationLogsTests {
    private func makeStore() throws -> CardStore {
        CardStore(container: try AnghkooeyModelContainer.makeInMemoryContainer())
    }

    @Test("projects and sorts review logs by (cardID, reviewedAt)")
    func projectionAndOrder() async throws {
        let store = try makeStore()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let engine = LiveFSRS6Engine()

        let snap = try await store.create(question: "q", answer: "a", sourceSpan: nil, now: now)
        let card = SchedulingCard.newCard(due: now)
        let out1 = try engine.next(card: card, rating: .good, now: now)
        try await store.apply(out1, to: snap.id, grade: .good, now: now)

        let day3 = now.addingTimeInterval(3 * 86_400)
        let out2 = try engine.next(card: out1.card, rating: .good, now: day3)
        try await store.apply(out2, to: snap.id, grade: .good, now: day3)

        let rows = try await store.optimizationReviewLogs()
        #expect(rows.count == 2)
        #expect(rows.allSatisfy { $0.cardID == snap.id })
        #expect(rows[0].reviewedAt <= rows[1].reviewedAt)
        #expect(rows[1].elapsedDays == 3)
    }

    @Test("skips orphaned logs with no card relationship")
    func orphanSkip() async throws {
        // An empty store yields no rows.
        let store = try makeStore()
        let rows = try await store.optimizationReviewLogs()
        #expect(rows.isEmpty)
    }

    @Test("multiple cards are grouped and sorted by cardID")
    func multipleCards() async throws {
        let store = try makeStore()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let engine = LiveFSRS6Engine()

        let snapA = try await store.create(question: "a", answer: "a", sourceSpan: nil, now: now)
        let snapB = try await store.create(question: "b", answer: "b", sourceSpan: nil, now: now)

        let out = try engine.next(card: SchedulingCard.newCard(due: now), rating: .good, now: now)
        try await store.apply(out, to: snapA.id, grade: .good, now: now)
        try await store.apply(try engine.next(card: SchedulingCard.newCard(due: now), rating: .hard, now: now),
                              to: snapB.id, grade: .hard, now: now)

        let rows = try await store.optimizationReviewLogs()
        #expect(rows.count == 2)
        // Within each card's group, rows are sorted by reviewedAt.
        let aRows = rows.filter { $0.cardID == snapA.id }
        let bRows = rows.filter { $0.cardID == snapB.id }
        #expect(aRows.count == 1)
        #expect(bRows.count == 1)
    }
}
