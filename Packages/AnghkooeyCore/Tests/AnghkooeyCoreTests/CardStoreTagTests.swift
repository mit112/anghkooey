import Testing
import Foundation
import SwiftData
import class AnghkooeyCore.Tag
@testable import AnghkooeyCore

@Suite("CardStore tags — Lane T")
struct CardStoreTagTests {

    // MARK: CardStore (actor)

    @Test("create with tags persists tag names in snapshot")
    func cardStore_create_withTags_persistsTagsInSnapshot() async throws {
        let container = try AnghkooeyModelContainer.makeInMemoryContainer()
        let store = CardStore(container: container)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let snap = try await store.create(
            question: "Q",
            answer: "A",
            sourceSpan: nil,
            tags: ["swift", "ios"],
            now: now
        )

        #expect(snap.tags.sorted() == ["ios", "swift"])
    }

    @Test("create with same tag name on two cards shares one Tag row")
    func cardStore_create_dedupsTags() async throws {
        let container = try AnghkooeyModelContainer.makeInMemoryContainer()
        let store = CardStore(container: container)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        _ = try await store.create(question: "Q1", answer: "A1", sourceSpan: nil, tags: ["swift"], now: now)
        _ = try await store.create(question: "Q2", answer: "A2", sourceSpan: nil, tags: ["swift"], now: now)

        let all = try await store.allCards()
        #expect(all.count == 2)
        #expect(all.allSatisfy { $0.tags == ["swift"] })
    }

    @Test("create with different-cased tag name reuses existing Tag")
    func cardStore_create_caseInsensitiveDedupsTags() async throws {
        let container = try AnghkooeyModelContainer.makeInMemoryContainer()
        let store = CardStore(container: container)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        _ = try await store.create(question: "Q1", answer: "A1", sourceSpan: nil, tags: ["Swift"], now: now)
        _ = try await store.create(question: "Q2", answer: "A2", sourceSpan: nil, tags: ["swift"], now: now)

        let all = try await store.allCards()
        #expect(all.allSatisfy { !$0.tags.isEmpty })
    }

    @Test("update(id:question:answer:tags:) replaces existing tags")
    func cardStore_update_withTags_replacesTags() async throws {
        let container = try AnghkooeyModelContainer.makeInMemoryContainer()
        let store = CardStore(container: container)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snap = try await store.create(question: "Q", answer: "A", sourceSpan: nil, tags: ["old"], now: now)

        try await store.update(id: snap.id, question: "Q", answer: "A", tags: ["new1", "new2"])

        let all = try await store.allCards()
        let updated = try #require(all.first(where: { $0.id == snap.id }))
        #expect(updated.tags.sorted() == ["new1", "new2"])
    }

    @Test("update(id:question:answer:tags:) with empty tags clears all tags")
    func cardStore_update_emptyTags_clearsTags() async throws {
        let container = try AnghkooeyModelContainer.makeInMemoryContainer()
        let store = CardStore(container: container)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snap = try await store.create(question: "Q", answer: "A", sourceSpan: nil, tags: ["swift"], now: now)

        try await store.update(id: snap.id, question: "Q", answer: "A", tags: [])

        let all = try await store.allCards()
        let updated = try #require(all.first(where: { $0.id == snap.id }))
        #expect(updated.tags.isEmpty)
    }

    // MARK: MockCardStore

    @Test("MockCardStore.create stores tags in snapshot")
    func mockCardStore_create_storesTags() async throws {
        let store = MockCardStore()
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let snap = try await store.create(
            question: "Q",
            answer: "A",
            sourceSpan: nil,
            tags: ["swift", "ios"],
            now: now
        )

        #expect(snap.tags.sorted() == ["ios", "swift"])
    }

    @Test("MockCardStore.update(id:question:answer:tags:) replaces tags in memory")
    func mockCardStore_update_withTags_replacesTags() async throws {
        let store = MockCardStore()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snap = try await store.create(question: "Q", answer: "A", sourceSpan: nil, tags: ["old"], now: now)

        try await store.update(id: snap.id, question: "Q", answer: "A", tags: ["new"])

        let updated = try #require(store.cards.first(where: { $0.id == snap.id }))
        #expect(updated.tags == ["new"])
    }

    // MARK: Orphaned tag pruning (#41)

    /// Fetches the persisted `Tag` row (if any) matching `name`'s normalized
    /// form, using a fresh `ModelContext` on the same container so the
    /// assertion is independent of any in-memory state `CardStore` holds.
    private func fetchTag(named name: String, in container: ModelContainer) throws -> Tag? {
        let context = ModelContext(container)
        let norm = Tag.normalize(name)
        let predicate = #Predicate<Tag> { $0.normalizedName == norm }
        return try context.fetch(FetchDescriptor<Tag>(predicate: predicate)).first
    }

    @Test("update(id:question:answer:tags:) removing a card's only tag prunes the now-orphaned Tag row")
    func cardStore_update_removingOnlyTag_prunesOrphanedTag() async throws {
        let container = try AnghkooeyModelContainer.makeInMemoryContainer()
        let store = CardStore(container: container)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snap = try await store.create(question: "Q", answer: "A", sourceSpan: nil, tags: ["temp"], now: now)

        try await store.update(id: snap.id, question: "Q", answer: "A", tags: [])

        #expect(try fetchTag(named: "temp", in: container) == nil)
    }

    @Test("update(id:question:answer:tags:) renaming a card's only tag prunes the old Tag and creates the new one")
    func cardStore_update_renamingTag_prunesOldTagCreatesNew() async throws {
        let container = try AnghkooeyModelContainer.makeInMemoryContainer()
        let store = CardStore(container: container)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snap = try await store.create(question: "Q", answer: "A", sourceSpan: nil, tags: ["Foo"], now: now)

        try await store.update(id: snap.id, question: "Q", answer: "A", tags: ["Bar"])

        #expect(try fetchTag(named: "foo", in: container) == nil)
        #expect(try fetchTag(named: "Bar", in: container) != nil)
    }

    @Test("update(id:question:answer:tags:) dropping a shared tag from one card does not prune it")
    func cardStore_update_droppingSharedTag_doesNotPrune() async throws {
        let container = try AnghkooeyModelContainer.makeInMemoryContainer()
        let store = CardStore(container: container)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snap1 = try await store.create(question: "Q1", answer: "A1", sourceSpan: nil, tags: ["shared"], now: now)
        _ = try await store.create(question: "Q2", answer: "A2", sourceSpan: nil, tags: ["shared"], now: now)

        try await store.update(id: snap1.id, question: "Q1", answer: "A1", tags: [])

        #expect(try fetchTag(named: "shared", in: container) != nil)
    }

    @Test("reads (allCards/dueCards) never prune Tag rows")
    func cardStore_reads_doNotPruneTags() async throws {
        let container = try AnghkooeyModelContainer.makeInMemoryContainer()
        let store = CardStore(container: container)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        _ = try await store.create(question: "Q", answer: "A", sourceSpan: nil, tags: ["solo"], now: now)

        _ = try await store.allCards()
        _ = try await store.dueCards(asOf: now)

        #expect(try fetchTag(named: "solo", in: container) != nil)
    }

    @Test("update with multiple tags prunes only the dropped orphan and keeps the retained tag attached")
    func cardStore_update_mixedRetainAndDrop_prunesOnlyDropped() async throws {
        let container = try AnghkooeyModelContainer.makeInMemoryContainer()
        let store = CardStore(container: container)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snap = try await store.create(question: "Q", answer: "A", sourceSpan: nil, tags: ["Foo", "Bar"], now: now)

        try await store.update(id: snap.id, question: "Q", answer: "A", tags: ["Bar"])

        // Only the dropped, now-orphaned tag is pruned; the retained one survives.
        #expect(try fetchTag(named: "foo", in: container) == nil)
        #expect(try fetchTag(named: "Bar", in: container) != nil)
        // ...and is still attached to the card.
        let all = try await store.allCards()
        let updated = try #require(all.first(where: { $0.id == snap.id }))
        #expect(updated.tags == ["Bar"])
    }
}
