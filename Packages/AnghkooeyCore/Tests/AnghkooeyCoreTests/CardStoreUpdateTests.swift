import Testing
import Foundation
@testable import AnghkooeyCore

@Suite("CardStore.update — Lane S")
struct CardStoreUpdateTests {

    // MARK: CardStore (actor)

    @Test("update changes question and answer on an existing card")
    func update_changesQuestionAndAnswer() async throws {
        let container = try AnghkooeyModelContainer.makeInMemoryContainer()
        let store = CardStore(container: container)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snap = try await store.create(question: "Old Q", answer: "Old A", sourceSpan: nil, now: now)

        try await store.update(id: snap.id, question: "New Q", answer: "New A")

        let all = try await store.allCards()
        let updated = try #require(all.first(where: { $0.id == snap.id }))
        #expect(updated.question == "New Q")
        #expect(updated.answer == "New A")
    }

    @Test("update with a nonexistent ID is a no-op and does not throw")
    func update_nonexistentID_doesNotThrow() async throws {
        let container = try AnghkooeyModelContainer.makeInMemoryContainer()
        let store = CardStore(container: container)
        // No cards created — passing any UUID should be a silent no-op.
        try await store.update(id: UUID(), question: "Q", answer: "A")
    }

    @Test("update does not modify FSRS scheduling fields")
    func update_doesNotModifyFSRSFields() async throws {
        let container = try AnghkooeyModelContainer.makeInMemoryContainer()
        let store = CardStore(container: container)
        let engine = LiveFSRS6Engine()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snap = try await store.create(question: "Q", answer: "A", sourceSpan: nil, now: now)
        let output = try engine.next(card: snap.schedulingCard, rating: .good, now: now)
        try await store.apply(output, to: snap.id, grade: .good, now: now)

        try await store.update(id: snap.id, question: "Edited Q", answer: "Edited A")

        let all = try await store.allCards()
        let updated = try #require(all.first(where: { $0.id == snap.id }))
        #expect(updated.stability == output.card.stability)
        #expect(updated.difficulty == output.card.difficulty)
        #expect(updated.state == output.card.state)
        #expect(abs(updated.dueAt.timeIntervalSince(output.card.due)) < 1)
    }

    // MARK: MockCardStore

    @Test("MockCardStore.update changes question and answer in memory")
    func mockCardStore_update_changesSnapshot() async throws {
        let store = MockCardStore()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snap = try await store.create(question: "Old Q", answer: "Old A", sourceSpan: nil, now: now)

        try await store.update(id: snap.id, question: "New Q", answer: "New A")

        let updated = try #require(store.cards.first(where: { $0.id == snap.id }))
        #expect(updated.question == "New Q")
        #expect(updated.answer == "New A")
    }

    @Test("MockCardStore.update with nonexistent ID is a no-op")
    func mockCardStore_update_nonexistentID_isNoOp() async throws {
        let store = MockCardStore()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        _ = try await store.create(question: "Q", answer: "A", sourceSpan: nil, now: now)
        let originalCount = store.cards.count

        try await store.update(id: UUID(), question: "X", answer: "Y")

        #expect(store.cards.count == originalCount)
    }

    @Test("MockCardStore.update throws when updateError is set")
    func mockCardStore_update_throwsOnError() async throws {
        let store = MockCardStore()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snap = try await store.create(question: "Q", answer: "A", sourceSpan: nil, now: now)
        store.updateError = PersistenceError.invalidShift(days: -1)

        await #expect(throws: (any Error).self) {
            try await store.update(id: snap.id, question: "X", answer: "Y")
        }
    }
}
