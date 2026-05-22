import Testing
import Foundation
import AnghkooeyCore
@testable import Anghkooey

@MainActor
@Suite("FreezeController")
struct FreezeControllerTests {

    @Test("initial state: not frozen")
    func initial_notFrozen() {
        let controller = FreezeController(
            cardStore: MockCardStore(),
            storage: InMemoryFreezeStorage()
        )
        #expect(controller.isFrozen == false)
        #expect(controller.frozenSince == nil)
    }

    @Test("freeze(now:) records timestamp")
    func freeze_recordsTimestamp() {
        let storage = InMemoryFreezeStorage()
        let controller = FreezeController(cardStore: MockCardStore(), storage: storage)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        controller.freeze(now: now)
        #expect(controller.isFrozen == true)
        #expect(controller.frozenSince == now)
        #expect(storage.frozenSince == now)
    }

    @Test("unfreeze after 3 days shifts all cards by 3 days")
    func unfreezeAfter3Days_shifts3() async throws {
        let store = MockCardStore()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        try await store.create(question: "q", answer: "a", sourceSpan: nil, now: start)
        let originalDue = try await store.allCards().first!.dueAt

        let controller = FreezeController(cardStore: store, storage: InMemoryFreezeStorage())
        controller.freeze(now: start)
        try await controller.unfreeze(now: start.addingTimeInterval(3 * 86_400))

        let after = try await store.allCards().first!.dueAt
        #expect(after == originalDue.addingTimeInterval(3 * 86_400))
        #expect(controller.isFrozen == false)
    }

    @Test("unfreeze same day: 0 days shift, state cleared")
    func unfreezeSameDay_noShift() async throws {
        let store = MockCardStore()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        try await store.create(question: "q", answer: "a", sourceSpan: nil, now: now)
        let originalDue = try await store.allCards().first!.dueAt

        let controller = FreezeController(cardStore: store, storage: InMemoryFreezeStorage())
        controller.freeze(now: now)
        try await controller.unfreeze(now: now.addingTimeInterval(3600))  // 1 hour later

        let after = try await store.allCards().first!.dueAt
        #expect(after == originalDue)
        #expect(controller.isFrozen == false)
    }

    @Test("unfreeze without freeze is a no-op")
    func unfreezeWithoutFreeze_noOp() async throws {
        let controller = FreezeController(
            cardStore: MockCardStore(),
            storage: InMemoryFreezeStorage()
        )
        try await controller.unfreeze(now: .now)
        #expect(controller.isFrozen == false)
    }
}

/// In-memory test double for `FreezeStorage`. Production uses UserDefaults; tests inject this.
final class InMemoryFreezeStorage: FreezeStorage {
    var frozenSince: Date?
}
