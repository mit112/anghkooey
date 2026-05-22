import Testing
import Foundation
import SwiftData
@testable import AnghkooeyCore

@Suite("CardStore mnemonic — Lane M")
struct CardStoreMnemonicTests {

    // MARK: Migration plan structure

    @Test("Migration plan has three schemas and two stages after V3 addition")
    func migrationPlan_hasThreeSchemasAndTwoStages() {
        #expect(AnghkooeyMigrationPlan.schemas.count == 3)
        #expect(AnghkooeyMigrationPlan.stages.count == 2)
    }

    // MARK: Snapshot defaults

    @Test("Fresh Card.Snapshot has mnemonic == nil")
    func freshSnapshot_mnemonicIsNil() async throws {
        let container = try AnghkooeyModelContainer.makeInMemoryContainer()
        let store = CardStore(container: container)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let snap = try await store.create(question: "Q", answer: "A", sourceSpan: nil, now: now)

        #expect(snap.mnemonic == nil)
    }

    // MARK: CardStore actor

    @Test("updateMnemonic persists and allCards reflects it in the Snapshot")
    func updateMnemonic_persistsAndSnapshotCarriesMnemonic() async throws {
        let container = try AnghkooeyModelContainer.makeInMemoryContainer()
        let store = CardStore(container: container)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snap = try await store.create(question: "Q", answer: "A", sourceSpan: nil, now: now)

        try await store.updateMnemonic(id: snap.id, mnemonic: "Picture a golden bridge.")

        let all = try await store.allCards()
        let updated = try #require(all.first { $0.id == snap.id })
        #expect(updated.mnemonic == "Picture a golden bridge.")
    }

    @Test("updateMnemonic on unknown id is a silent no-op")
    func updateMnemonic_unknownId_isNoOp() async throws {
        let container = try AnghkooeyModelContainer.makeInMemoryContainer()
        let store = CardStore(container: container)
        // Should not throw
        try await store.updateMnemonic(id: UUID(), mnemonic: "anything")
    }

    @Test("updateMnemonic can overwrite an existing mnemonic")
    func updateMnemonic_canOverwrite() async throws {
        let container = try AnghkooeyModelContainer.makeInMemoryContainer()
        let store = CardStore(container: container)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snap = try await store.create(question: "Q", answer: "A", sourceSpan: nil, now: now)

        try await store.updateMnemonic(id: snap.id, mnemonic: "First mnemonic.")
        try await store.updateMnemonic(id: snap.id, mnemonic: "Second mnemonic.")

        let all = try await store.allCards()
        let updated = try #require(all.first { $0.id == snap.id })
        #expect(updated.mnemonic == "Second mnemonic.")
    }

    // MARK: MockCardStore

    @Test("MockCardStore.updateMnemonic stores mnemonic on matching card")
    func mockStore_updateMnemonic_storesMnemonic() async throws {
        let store = MockCardStore()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snap = try await store.create(question: "Q", answer: "A", sourceSpan: nil, now: now)

        try await store.updateMnemonic(id: snap.id, mnemonic: "Think of a flamingo.")

        let all = try await store.allCards()
        let updated = try #require(all.first { $0.id == snap.id })
        #expect(updated.mnemonic == "Think of a flamingo.")
    }

    @Test("MockCardStore.updateMnemonic on unknown id is no-op")
    func mockStore_updateMnemonic_unknownId_isNoOp() async throws {
        let store = MockCardStore()
        try await store.updateMnemonic(id: UUID(), mnemonic: "ignored")
        #expect(store.cards.isEmpty)
    }

    @Test("MockCardStore.shiftAllDueDates preserves mnemonic field")
    func mockStore_shiftDueDates_preservesMnemonic() async throws {
        let store = MockCardStore()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snap = try await store.create(question: "Q", answer: "A", sourceSpan: nil, now: now)
        try await store.updateMnemonic(id: snap.id, mnemonic: "Preserved mnemonic.")

        try await store.shiftAllDueDates(byDays: 1)

        let all = try await store.allCards()
        let updated = try #require(all.first { $0.id == snap.id })
        #expect(updated.mnemonic == "Preserved mnemonic.")
    }
}
