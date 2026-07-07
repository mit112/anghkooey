import Foundation
import Testing
@testable import AnghkooeyUI
@testable import AnghkooeyCore
import AnghkooeyIntelligence

@Suite struct ClozeAuthoringViewModelTests {
    @MainActor @Test func acceptDisabledUntilMarkupValid() {
        let vm = ClozeAuthoringViewModel(store: MockCardStore(), authoringService: MockClozeAuthoringService())
        vm.markedText = "plain text, no deletions"
        #expect(vm.canAccept == false)
        vm.markedText = "The {{c1::mitochondria}} is the powerhouse"
        #expect(vm.canAccept == true)
    }

    @MainActor @Test func acceptFansOutSiblings() async throws {
        let store = MockCardStore()
        let vm = ClozeAuthoringViewModel(store: store, authoringService: MockClozeAuthoringService())
        vm.markedText = "The {{c1::a}} and the {{c2::b}}"
        try await vm.accept(tags: ["bio"], now: .now)
        #expect(store.cards.count == 2)
    }

    // MARK: - #25: Generate must not swallow failures or destroy the user's text

    @MainActor @Test func generateFailureSetsGenericTryAgainMessageAndPreservesText() async {
        let service = MockClozeAuthoringService()
        service.error = NSError(domain: "test", code: 1)
        let vm = ClozeAuthoringViewModel(store: MockCardStore(), authoringService: service)
        let original = "The mitochondria is the powerhouse of the cell"
        vm.markedText = original

        await vm.generate()

        #expect(vm.errorMessage != nil)
        #expect(vm.errorMessage?.contains("try again") == true)
        #expect(vm.markedText == original)
        #expect(vm.canRevert == false)
    }

    @MainActor @Test func generateFailureDistinguishesAIUnavailableFromGenericFailure() async {
        let service = MockClozeAuthoringService()
        service.configuredAvailability = .unavailable(reason: .deviceNotEligible)
        let vm = ClozeAuthoringViewModel(store: MockCardStore(), authoringService: service)
        let original = "The mitochondria is the powerhouse of the cell"
        vm.markedText = original

        await vm.generate()

        #expect(vm.errorMessage != nil)
        #expect(vm.errorMessage?.localizedCaseInsensitiveContains("available") == true)
        #expect(vm.errorMessage?.contains("try again") == false)
        #expect(vm.markedText == original)
        #expect(vm.canRevert == false)
    }

    @MainActor @Test func generateSuccessReplacesTextAndRevertRestoresPreGenerationText() async {
        let service = MockClozeAuthoringService()
        service.stubbed = [ClozeDraft(markedText: "The {{c1::mitochondria}} is the powerhouse", proposedTags: ["bio"])]
        let vm = ClozeAuthoringViewModel(store: MockCardStore(), authoringService: service)
        let original = "The mitochondria is the powerhouse of the cell"
        vm.markedText = original

        await vm.generate()

        #expect(vm.markedText == "The {{c1::mitochondria}} is the powerhouse")
        #expect(vm.canRevert == true)

        vm.revert()

        #expect(vm.markedText == original)
        #expect(vm.canRevert == false)
    }

    @MainActor @Test func generateWithNoDraftsSetsNoDeletionsFoundMessageAndPreservesText() async {
        let service = MockClozeAuthoringService()
        service.stubbed = [] // model legitimately returns nothing — no throw
        let vm = ClozeAuthoringViewModel(store: MockCardStore(), authoringService: service)
        let original = "The mitochondria is the powerhouse of the cell"
        vm.markedText = original

        await vm.generate()

        #expect(vm.errorMessage != nil)
        #expect(vm.errorMessage?.contains("No cloze deletions found") == true)
        #expect(vm.markedText == original)
    }

    @MainActor @Test func acceptWithInvalidMarkupThrowsAndSetsErrorMessage() async {
        let vm = ClozeAuthoringViewModel(store: MockCardStore(), authoringService: MockClozeAuthoringService())
        vm.markedText = "plain text, no deletions"

        await #expect(throws: (any Error).self) {
            try await vm.accept(tags: [])
        }

        #expect(vm.errorMessage != nil)
    }
}
