import Testing
import Foundation
@testable import AnghkooeyCore

@Suite struct CardStoreClozeTests {
    private func makeStore() throws -> CardStore {
        CardStore(container: try AnghkooeyModelContainer.makeInMemoryContainer())
    }

    @Test func fanOutCreatesOneCardPerDeletion() async throws {
        let store = try makeStore()
        let t = try ClozeMarkupParser.parse("The {{c1::mitochondria}} is the {{c2::powerhouse}} of the cell")
        let snaps = try await store.createClozeCards(from: t, tags: ["bio"], now: .now)
        #expect(snaps.count == 2)
        #expect(Set(snaps.map(\.question)).count == 2)
        #expect(Set(snaps.compactMap(\.clozeGroupID)).count == 1)
    }

    @Test func reviewingOneSiblingBuriesOthersUntilNextDay() async throws {
        let store = try makeStore()
        let t = try ClozeMarkupParser.parse("The {{c1::a}} and the {{c2::b}}")
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snaps = try await store.createClozeCards(from: t, tags: [], now: now)
        // Both due now.
        #expect(try await store.dueCards(asOf: now).count == 2)
        // Review the first sibling.
        let engine = LiveFSRS6Engine()
        let out = try engine.next(card: snaps[0].schedulingCard, rating: .good, now: now)
        try await store.apply(out, to: snaps[0].id, grade: .good, now: now)
        // Same day: the other sibling is buried, so only 0 remain due (reviewed one rescheduled).
        let dueSameDay = try await store.dueCards(asOf: now.addingTimeInterval(60))
        #expect(dueSameDay.allSatisfy { $0.id != snaps[1].id })
        // Next day: sibling resurfaces.
        let nextDay = now.addingTimeInterval(86_400 + 60)
        #expect(try await store.dueCards(asOf: nextDay).contains { $0.id == snaps[1].id })
    }
}
