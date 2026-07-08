import Testing
import Foundation
import SwiftData
import class AnghkooeyCore.Tag
@testable import AnghkooeyCore

/// Coverage for `CardStoreProtocol.delete(id:)` (#38). Deleting a card must:
///   - remove it from `allCards()`
///   - cascade its `ReviewLog`s (via the SwiftData `.cascade` delete rule)
///   - prune a tag that becomes orphaned, but never a tag another card still uses
///   - never delete cloze siblings, which share only `clozeGroupID`
///   - be a silent no-op for an unknown id, matching `update(id:...)`
@Suite("CardStore.delete — Lane D")
struct CardStoreDeleteTests {

    private func fetchTag(named name: String, in container: ModelContainer) throws -> Tag? {
        let context = ModelContext(container)
        let norm = Tag.normalize(name)
        let predicate = #Predicate<Tag> { $0.normalizedName == norm }
        return try context.fetch(FetchDescriptor<Tag>(predicate: predicate)).first
    }

    // MARK: CardStore (actor)

    @Test("delete removes the card from allCards()")
    func delete_removesCardFromAllCards() async throws {
        let container = try AnghkooeyModelContainer.makeInMemoryContainer()
        let store = CardStore(container: container)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snap = try await store.create(question: "Q", answer: "A", sourceSpan: nil, now: now)

        try await store.delete(id: snap.id)

        let all = try await store.allCards()
        #expect(!all.contains { $0.id == snap.id })
    }

    @Test("delete cascades the card's ReviewLogs without throwing")
    func delete_cascadesReviewLogs() async throws {
        let container = try AnghkooeyModelContainer.makeInMemoryContainer()
        let store = CardStore(container: container)
        let engine = LiveFSRS6Engine()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snap = try await store.create(question: "Q", answer: "A", sourceSpan: nil, now: now)
        let output = try engine.next(card: snap.schedulingCard, rating: .good, now: now)
        try await store.apply(output, to: snap.id, grade: .good, now: now)

        try await store.delete(id: snap.id)

        let rows = try await store.optimizationReviewLogs()
        #expect(!rows.contains { $0.cardID == snap.id })
    }

    @Test("delete prunes a tag that becomes orphaned")
    func delete_prunesOrphanedTag() async throws {
        let container = try AnghkooeyModelContainer.makeInMemoryContainer()
        let store = CardStore(container: container)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snap = try await store.create(question: "Q", answer: "A", sourceSpan: nil, tags: ["temp"], now: now)

        try await store.delete(id: snap.id)

        #expect(try fetchTag(named: "temp", in: container) == nil)
    }

    @Test("delete does not prune a tag still used by another card")
    func delete_sharedTag_doesNotPruneUntilLastCardDeleted() async throws {
        let container = try AnghkooeyModelContainer.makeInMemoryContainer()
        let store = CardStore(container: container)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snap1 = try await store.create(question: "Q1", answer: "A1", sourceSpan: nil, tags: ["shared"], now: now)
        let snap2 = try await store.create(question: "Q2", answer: "A2", sourceSpan: nil, tags: ["shared"], now: now)

        try await store.delete(id: snap1.id)
        #expect(try fetchTag(named: "shared", in: container) != nil)

        try await store.delete(id: snap2.id)
        #expect(try fetchTag(named: "shared", in: container) == nil)
    }

    @Test("deleting one cloze sibling leaves the others intact")
    func delete_clozeSibling_leavesOthersIntact() async throws {
        let container = try AnghkooeyModelContainer.makeInMemoryContainer()
        let store = CardStore(container: container)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let template = try ClozeMarkupParser.parse("The capital of France is {{c1::Paris}} and of Germany is {{c2::Berlin}}.")
        let siblings = try await store.createClozeCards(from: template, tags: [], now: now)
        #expect(siblings.count == 2)

        try await store.delete(id: siblings[0].id)

        let all = try await store.allCards()
        #expect(!all.contains { $0.id == siblings[0].id })
        #expect(all.contains { $0.id == siblings[1].id })
    }

    @Test("delete with an unknown id is a silent no-op")
    func delete_unknownID_isSilentNoOp() async throws {
        let container = try AnghkooeyModelContainer.makeInMemoryContainer()
        let store = CardStore(container: container)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        _ = try await store.create(question: "Q", answer: "A", sourceSpan: nil, now: now)
        let countBefore = try await store.allCards().count

        try await store.delete(id: UUID())

        let countAfter = try await store.allCards().count
        #expect(countAfter == countBefore)
    }

    // MARK: MockCardStore

    @Test("MockCardStore.delete removes the card by id")
    func mockCardStore_delete_removesCard() async throws {
        let store = MockCardStore()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snap = try await store.create(question: "Q", answer: "A", sourceSpan: nil, now: now)

        try await store.delete(id: snap.id)

        #expect(!store.cards.contains { $0.id == snap.id })
    }

    @Test("MockCardStore.delete with an unknown id is a no-op")
    func mockCardStore_delete_unknownID_isNoOp() async throws {
        let store = MockCardStore()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        _ = try await store.create(question: "Q", answer: "A", sourceSpan: nil, now: now)
        let countBefore = store.cards.count

        try await store.delete(id: UUID())

        #expect(store.cards.count == countBefore)
    }

    @Test("MockCardStore.delete throws when deleteError is set")
    func mockCardStore_delete_throwsOnError() async throws {
        let store = MockCardStore()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snap = try await store.create(question: "Q", answer: "A", sourceSpan: nil, now: now)
        store.deleteError = PersistenceError.invalidShift(days: -1)

        await #expect(throws: (any Error).self) {
            try await store.delete(id: snap.id)
        }
        // The card must still be present since the throw happened before removal.
        #expect(store.cards.contains { $0.id == snap.id })
    }
}
