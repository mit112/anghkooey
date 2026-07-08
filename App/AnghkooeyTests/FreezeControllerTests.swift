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

    @Test("unfreeze shifts by floor(elapsed / 86_400) days — 1 day 16h elapsed shifts by 1, not 2")
    func unfreeze_shiftsByFloorDays() async throws {
        let store = MockCardStore()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let controller = FreezeController(cardStore: store, storage: InMemoryFreezeStorage())
        controller.freeze(now: start)

        // 1 day + 16h elapsed: floor(40h / 24h) == 1, not 1.67 rounded up to 2.
        try await controller.unfreeze(now: start.addingTimeInterval(40 * 3_600))

        #expect(store.lastShiftDays == 1)
    }

    @Test("unfreeze failure leaves frozen state intact and rethrows")
    func unfreezeFailure_leavesFrozenStateIntactAndRethrows() async throws {
        struct StubShiftError: Error {}
        let store = MockCardStore()
        store.shiftError = StubShiftError()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let controller = FreezeController(cardStore: store, storage: InMemoryFreezeStorage())
        controller.freeze(now: start)

        await #expect(throws: StubShiftError.self) {
            try await controller.unfreeze(now: start.addingTimeInterval(2 * 86_400))
        }

        // The toggle's `get` reads `isFrozen`; a failed unfreeze must leave the
        // frozen state intact so the Settings toggle reverts back to on.
        #expect(controller.isFrozen == true)
    }

    // MARK: - #96 double-unfreeze reentrancy

    /// Waits for `condition` to become true by cooperatively yielding the
    /// MainActor. Bounded so a genuine regression fails fast instead of
    /// hanging. Mirrors `AppStateAcceptDraftReentrancyTests.waitUntil`.
    private func waitUntil(
        maxIterations: Int = 10_000,
        _ condition: () -> Bool
    ) async {
        for _ in 0..<maxIterations {
            if condition() { return }
            await Task.yield()
        }
    }

    @Test("two overlapping unfreeze() calls shift the deck only once, not twice (#96)")
    func overlappingUnfreezeCallsShiftOnlyOnce() async throws {
        let store = ShiftGateCardStore()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let controller = FreezeController(cardStore: store, storage: InMemoryFreezeStorage())
        controller.freeze(now: start)

        let unfreezeAt = start.addingTimeInterval(3 * 86_400)

        // First call (e.g. the Settings "I'm away" toggle flipped off):
        // enters `unfreeze`, reads `frozenSince`, and suspends inside
        // `shiftAllDueDates` before it ever clears the frozen state.
        let taskA = Task { @MainActor in
            try await controller.unfreeze(now: unfreezeAt)
        }

        // Confirm task A is genuinely parked inside `shiftAllDueDates`
        // (i.e. `frozenSince` is still non-nil) before task B starts.
        await waitUntil { store.shiftCallCount >= 1 }

        // Second call: a rapid double-toggle firing while task A's shift is
        // still in flight. Before the #96 fix this also reads
        // `frozenSince != nil`, calls `shiftAllDueDates` a second time, and
        // the deck slides forward by 2× the away-days once both resolve.
        let taskB = Task { @MainActor in
            try await controller.unfreeze(now: unfreezeAt)
        }
        await Task.yield()
        await Task.yield()

        // Release whatever is parked — one call if the guard held, two if it
        // didn't — so the test resolves deterministically either way instead
        // of hanging on a regression.
        store.releaseAll()
        try await taskA.value
        try await taskB.value

        #expect(store.shiftCallCount == 1)
        #expect(store.lastShiftDays == 3)
        #expect(controller.isFrozen == false)
        #expect(controller.frozenSince == nil)
    }

    @Test("a freeze() during an in-flight unfreeze() is preserved, not clobbered when the unfreeze resumes (#96 compare-and-clear)")
    func freezeDuringInFlightUnfreeze_isPreserved() async throws {
        let store = ShiftGateCardStore()
        let storage = InMemoryFreezeStorage()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let controller = FreezeController(cardStore: store, storage: storage)
        controller.freeze(now: start)

        let unfreezeAt = start.addingTimeInterval(3 * 86_400)
        // Unfreeze enters, reads `frozenSince`, and parks inside the shift
        // before it clears the frozen state.
        let task = Task { @MainActor in try await controller.unfreeze(now: unfreezeAt) }
        await waitUntil { store.shiftCallCount >= 1 }

        // The user re-freezes (rapid toggle off→on) while the shift is still in
        // flight. `freeze()` is intentionally not blocked by `isUnfreezing`.
        let refreezeAt = unfreezeAt.addingTimeInterval(60)
        controller.freeze(now: refreezeAt)

        store.releaseAll()
        try await task.value

        // Compare-and-clear: the resumed unfreeze cleared the freeze it
        // processed (`start`) only — the newer freeze period survives. Before
        // the fix the unconditional clear deleted it (isFrozen would be false).
        #expect(controller.isFrozen == true)
        #expect(controller.frozenSince == refreezeAt)
    }
}

/// Test-only `CardStoreProtocol` stub whose `shiftAllDueDates(byDays:)`
/// suspends on a continuation the test controls, so two overlapping
/// `FreezeController.unfreeze()` calls can be forced to genuinely race
/// (#96). `MockCardStore` exposes suspension gates for `create`/`apply`/
/// `update`/`delete`/`optimizationReviewLogs` but not for
/// `shiftAllDueDates`, so this is a standalone stub rather than an
/// extension of it. `FreezeController` only ever calls
/// `shiftAllDueDates(byDays:)` on its `cardStore` — every other protocol
/// requirement below is unreachable for this test and stubs out with
/// `fatalError`. Mirrors the `AwaitGate` suspension idiom used in
/// `AppStateAcceptDraftReentrancyTests`.
@MainActor
private final class ShiftGateCardStore: CardStoreProtocol, @unchecked Sendable {
    private(set) var shiftCallCount = 0
    private(set) var lastShiftDays: Int?
    private var pending: [CheckedContinuation<Void, Never>] = []

    /// Resumes every call currently parked inside `shiftAllDueDates`.
    func releaseAll() {
        let waiting = pending
        pending.removeAll()
        waiting.forEach { $0.resume() }
    }

    func shiftAllDueDates(byDays days: Int) async throws {
        shiftCallCount += 1
        lastShiftDays = days
        await withCheckedContinuation { continuation in
            pending.append(continuation)
        }
    }

    func create(question: String, answer: String, sourceSpan: String?, tags: [String], now: Date) async throws -> Card.Snapshot {
        fatalError("ShiftGateCardStore.create is unused by FreezeController")
    }

    func dueCards(asOf now: Date) async throws -> [Card.Snapshot] {
        fatalError("ShiftGateCardStore.dueCards is unused by FreezeController")
    }

    func apply(_ output: SchedulerOutput, to cardID: UUID, grade: Rating, now: Date) async throws {
        fatalError("ShiftGateCardStore.apply is unused by FreezeController")
    }

    func count(asOf now: Date) async throws -> (total: Int, due: Int) {
        fatalError("ShiftGateCardStore.count is unused by FreezeController")
    }

    func allCards() async throws -> [Card.Snapshot] {
        fatalError("ShiftGateCardStore.allCards is unused by FreezeController")
    }

    @discardableResult
    func update(id: UUID, question: String, answer: String, tags: [String]) async throws -> Card.Snapshot? {
        fatalError("ShiftGateCardStore.update is unused by FreezeController")
    }

    func updateMnemonic(id: UUID, mnemonic: String) async throws {
        fatalError("ShiftGateCardStore.updateMnemonic is unused by FreezeController")
    }

    func findBySourceSpan(_ span: String) async throws -> Card.Snapshot? {
        fatalError("ShiftGateCardStore.findBySourceSpan is unused by FreezeController")
    }

    func createImported(
        question: String, answer: String, sourceSpan: String?, tags: [String], dueAt: Date, now: Date
    ) async throws -> Card.Snapshot {
        fatalError("ShiftGateCardStore.createImported is unused by FreezeController")
    }

    func createClozeCards(from template: ClozeTemplate, tags: [String], now: Date) async throws -> [Card.Snapshot] {
        fatalError("ShiftGateCardStore.createClozeCards is unused by FreezeController")
    }

    func optimizationReviewLogs() async throws -> [OptimizationReviewLogRow] {
        fatalError("ShiftGateCardStore.optimizationReviewLogs is unused by FreezeController")
    }

    func nextDueDate(after now: Date) async throws -> Date? {
        fatalError("ShiftGateCardStore.nextDueDate is unused by FreezeController")
    }

    func delete(id: UUID) async throws {
        fatalError("ShiftGateCardStore.delete is unused by FreezeController")
    }
}

/// In-memory test double for `FreezeStorage`. Production uses UserDefaults; tests inject this.
final class InMemoryFreezeStorage: FreezeStorage {
    var frozenSince: Date?
}
