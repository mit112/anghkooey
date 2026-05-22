import Testing
import Foundation
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
}
