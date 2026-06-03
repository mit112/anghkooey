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
}
