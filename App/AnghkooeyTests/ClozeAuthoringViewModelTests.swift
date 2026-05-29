import Testing
@testable import AnghkooeyUI
@testable import AnghkooeyCore

@Suite struct ClozeAuthoringViewModelTests {
    @MainActor @Test func acceptDisabledUntilMarkupValid() {
        let vm = ClozeAuthoringViewModel(store: MockCardStore())
        vm.markedText = "plain text, no deletions"
        #expect(vm.canAccept == false)
        vm.markedText = "The {{c1::mitochondria}} is the powerhouse"
        #expect(vm.canAccept == true)
    }

    @MainActor @Test func acceptFansOutSiblings() async throws {
        let store = MockCardStore()
        let vm = ClozeAuthoringViewModel(store: store)
        vm.markedText = "The {{c1::a}} and the {{c2::b}}"
        try await vm.accept(tags: ["bio"], now: .now)
        #expect(store.cards.count == 2)
    }
}
