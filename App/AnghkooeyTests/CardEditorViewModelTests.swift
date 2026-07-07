import Testing
import Foundation
@testable import AnghkooeyUI
import AnghkooeyCore

@MainActor @Suite struct CardEditorViewModelTests {
    @Test func createModeStartsEmptyAndInvalid() {
        let vm = CardEditorViewModel(mode: .create, store: MockCardStore())
        #expect(vm.question.isEmpty)
        #expect(vm.answer.isEmpty)
        #expect(vm.canSave == false)
    }

    @Test func becomesValidWhenBothFieldsNonEmpty() {
        let vm = CardEditorViewModel(mode: .create, store: MockCardStore())
        vm.question = "  Capital of France?  "
        vm.answer = "Paris"
        #expect(vm.canSave == true)
    }

    @Test func whitespaceOnlyIsInvalid() {
        let vm = CardEditorViewModel(mode: .create, store: MockCardStore())
        vm.question = "   "; vm.answer = "   "
        #expect(vm.canSave == false)
    }

    @Test func saveCreatesCardInStore() async throws {
        let store = MockCardStore()
        let vm = CardEditorViewModel(mode: .create, store: store)
        vm.question = "2+2?"; vm.answer = "4"; vm.tags = ["Math"]
        try await vm.save()
        let all = try await store.allCards()
        #expect(all.contains { $0.question == "2+2?" && $0.answer == "4" })
    }

    @Test func clozeModeBuildsTemplateAndCreatesCards() async throws {
        let store = MockCardStore()
        let vm = CardEditorViewModel(mode: .create, store: store)
        vm.kind = .cloze
        vm.clozeText = "The capital of France is {{c1::Paris}}."
        #expect(vm.canSave == true)
        try await vm.save()
        let all = try await store.allCards()
        #expect(all.contains { $0.question.contains("capital of France") })
    }

    @Test func clozeWithoutDeletionIsInvalid() {
        let vm = CardEditorViewModel(mode: .create, store: MockCardStore())
        vm.kind = .cloze
        vm.clozeText = "No deletions here."
        #expect(vm.canSave == false)
    }

    // MARK: - #26: save() failures must surface, not vanish silently

    @Test func createSaveFailureSetsErrorMessageAndPreservesEnteredData() async {
        let store = MockCardStore()
        store.createError = PersistenceError.containerCreationFailed(underlying: NSError(domain: "test", code: 1))
        let vm = CardEditorViewModel(mode: .create, store: store)
        vm.question = "2+2?"; vm.answer = "4"; vm.tags = ["Math"]

        await #expect(throws: (any Error).self) {
            try await vm.save()
        }

        #expect(vm.errorMessage != nil)
        #expect(vm.question == "2+2?")
        #expect(vm.answer == "4")
        #expect(vm.tags == ["Math"])
        #expect(vm.isSaving == false)
    }

    @Test func editSaveFailureSetsErrorMessageAndPreservesEnteredData() async {
        let store = MockCardStore()
        store.updateError = PersistenceError.invalidShift(days: -1)
        let card = Card.Snapshot(
            id: UUID(),
            question: "Original question", answer: "Original answer",
            state: .review, stability: 1, difficulty: 5, dueAt: .now
        )
        let vm = CardEditorViewModel(mode: .edit(card), store: store)
        vm.question = "Edited question"; vm.answer = "Edited answer"; vm.tags = ["Edited"]

        await #expect(throws: (any Error).self) {
            try await vm.save()
        }

        #expect(vm.errorMessage != nil)
        #expect(vm.question == "Edited question")
        #expect(vm.answer == "Edited answer")
        #expect(vm.tags == ["Edited"])
        #expect(vm.isSaving == false)
    }

    @Test func isSavingIsFalseAfterSuccessfulSave() async throws {
        let store = MockCardStore()
        let vm = CardEditorViewModel(mode: .create, store: store)
        vm.question = "2+2?"; vm.answer = "4"
        try await vm.save()
        #expect(vm.isSaving == false)
    }

    @Test func successfulSaveClearsPriorErrorMessage() async throws {
        let store = MockCardStore()
        store.createError = PersistenceError.containerCreationFailed(underlying: NSError(domain: "test", code: 1))
        let vm = CardEditorViewModel(mode: .create, store: store)
        vm.question = "2+2?"; vm.answer = "4"
        await #expect(throws: (any Error).self) {
            try await vm.save()
        }
        #expect(vm.errorMessage != nil)

        store.createError = nil
        try await vm.save()
        #expect(vm.errorMessage == nil)
    }

    // MARK: - #26 review fixes: reentrancy guard + cloze-parse throws

    /// Controllable suspension point standing in for the real (actor-isolated)
    /// `CardStore`'s genuine cross-actor hop on `create(...)`. `MockCardStore`
    /// is a plain class, not an actor, so without this seam its `create(...)`
    /// never truly suspends — two overlapping `save()` calls would just run
    /// fully sequentially and the double-submit race this suite exists to
    /// catch could never be reproduced deterministically. Mirrors the
    /// `AwaitGate` pattern in `AppStateAcceptDraftReentrancyTests`.
    @MainActor
    private final class SaveAwaitGate: @unchecked Sendable {
        private var pending: [CheckedContinuation<Void, Never>] = []
        private(set) var callCount = 0

        func wait() async {
            await withCheckedContinuation { continuation in
                callCount += 1
                pending.append(continuation)
            }
        }

        func fireOldest() {
            guard !pending.isEmpty else { return }
            pending.removeFirst().resume()
        }
    }

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

    @Test("a second save() call that overlaps the first's in-flight create is a no-op: only one card is ever created")
    func overlappingSaveDoesNotDoubleCreateCard() async throws {
        let store = MockCardStore()
        let gate = SaveAwaitGate()
        let vm = CardEditorViewModel(mode: .create, store: store)
        vm.question = "2+2?"; vm.answer = "4"

        store.createGate = { await gate.wait() }

        // Tap 1: starts save(), which suspends inside the gated `store.create`.
        let taskA = Task { @MainActor in
            try await vm.save()
        }

        // Confirm task A is genuinely suspended inside the gate before firing
        // the overlapping call — otherwise this wouldn't exercise the guard.
        await waitUntil { gate.callCount >= 1 }
        #expect(vm.isSaving == true)

        // Tap 2: a rapid double-tap firing while save() #1 is still in
        // flight. Must be a no-op — it must not enqueue a second
        // `store.create` call.
        try await vm.save()

        gate.fireOldest()
        try await taskA.value

        #expect(store.cards.count == 1)
        #expect(store.cards.first?.question == "2+2?")
        #expect(store.cards.first?.answer == "4")
        #expect(vm.isSaving == false)
    }

    @Test("cloze save with unparseable markup throws instead of silently returning success")
    func clozeSaveWithUnparseableMarkupThrowsAndSetsErrorMessage() async {
        let store = MockCardStore()
        let vm = CardEditorViewModel(mode: .create, store: store)
        vm.kind = .cloze
        vm.clozeText = "The capital of France is {{c1::Paris" // missing closing `}}`

        await #expect(throws: (any Error).self) {
            try await vm.save()
        }

        #expect(vm.errorMessage != nil)
        #expect(store.cards.isEmpty)
        #expect(vm.isSaving == false)
    }
}
