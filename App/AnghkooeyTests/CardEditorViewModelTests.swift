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
}
