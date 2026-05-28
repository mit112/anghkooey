import Testing
import Foundation
@testable import AnghkooeyCore

@Suite("Cumulative LTM count")
struct LTMCountTests {

    private func snapshot(stability: Double, dueInDays: Double = 0) -> Card.Snapshot {
        Card.Snapshot(
            id: UUID(),
            question: "q", answer: "a",
            state: .review,
            stability: stability,
            difficulty: 5,
            dueAt: Date(timeIntervalSinceReferenceDate: dueInDays * 86_400)
        )
    }

    @Test("threshold default is 21 days")
    func defaultThreshold() {
        #expect(LTMConfig.defaultThresholdDays == 21)
    }

    @Test("a card at exactly the threshold counts")
    func boundaryInclusive() {
        let cards = [snapshot(stability: 21)]
        #expect(LTMConfig.count(cards, thresholdDays: 21) == 1)
    }

    @Test("a card just below the threshold does not count")
    func belowThreshold() {
        let cards = [snapshot(stability: 20.999)]
        #expect(LTMConfig.count(cards, thresholdDays: 21) == 0)
    }

    @Test("a brand-new card with zero stability never counts")
    func newCardExcluded() {
        let cards = [snapshot(stability: 0)]
        #expect(LTMConfig.count(cards, thresholdDays: 21) == 0)
    }

    @Test("count is independent of due date — overdue committed cards still count")
    func dueDateIrrelevant() {
        let cards = [snapshot(stability: 50, dueInDays: -100)]
        #expect(LTMConfig.count(cards, thresholdDays: 21) == 1)
    }

    @Test("mixed deck counts only cards over threshold")
    func mixedDeck() {
        let cards = [
            snapshot(stability: 0),
            snapshot(stability: 5),
            snapshot(stability: 21),
            snapshot(stability: 365),
        ]
        #expect(LTMConfig.count(cards, thresholdDays: 21) == 2)
    }
}

@Suite("LTM count via store")
@MainActor
struct LTMStoreCountTests {

    @Test("MockCardStore reports LTM count over threshold")
    func mockStoreCounts() async throws {
        let store = MockCardStore()
        _ = try await store.create(question: "a", answer: "a", sourceSpan: nil, tags: [], now: .now)
        let count = try await store.longTermMemoryCount(thresholdDays: 21)
        #expect(count == 0) // a freshly-created card has stability 0
    }
}
