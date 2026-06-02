import Testing
import Foundation
@testable import Anghkooey
import AnghkooeyCore
import AnghkooeyIntelligence

// MARK: - M4.2 contract tests
//
// These tests are RED until Codex implements AppState.enqueue(resolvedText:)
// to call cardAuthor.author(from:) instead of using the hardcoded fallback stub.

private struct FailingAuthor: CardAuthoringService {
    var availability: AuthoringAvailability {
        get async { .available }
    }

    func generateDrafts(from text: String) async throws -> AsyncThrowingStream<CardDraft, Error> {
        throw AuthoringError.generationFailed(underlying: URLError(.timedOut))
    }
}

@Suite("AppState.enqueue — M4.2 contract")
@MainActor
struct AppStateEnqueueTests {

    // MARK: enqueue_runsCardAuthor_andQueuesDraft

    @Test("enqueue calls cardAuthor and queues the returned draft")
    func enqueue_runsCardAuthor_andQueuesDraft() async throws {
        let expected = CardDraft(question: "What is the capital of France?", answer: "Paris")
        let mock = MockCardAuthoringService(drafts: [expected])
        let sut = AppState(cardAuthor: mock)

        await sut.enqueue(resolvedText: "France's capital is Paris.")

        let presented = try #require(sut.presentedDraft)
        #expect(presented.draft.question == expected.question)
        #expect(presented.draft.answer == expected.answer)
    }

    // MARK: enqueue_onAuthoringFailure_queuesFallbackDraft

    @Test("enqueue queues a fallback draft when cardAuthor throws")
    func enqueue_onAuthoringFailure_queuesFallbackDraft() async throws {
        let mock = MockCardAuthoringService(
            error: AuthoringError.generationFailed(underlying: NSError(domain: "test", code: 1))
        )
        let sut = AppState(cardAuthor: mock)
        let resolvedText = "Some captured text"

        await sut.enqueue(resolvedText: resolvedText)

        let presented = try #require(sut.presentedDraft)
        #expect(presented.draft.question == resolvedText)
        #expect(presented.draft.answer == "")
    }

    @Test("enqueue queues a fallback draft when model is unavailable (airplane-mode path)")
    func enqueue_onModelUnavailable_queuesFallbackDraft() async throws {
        let mock = MockCardAuthoringService(
            error: AuthoringError.unavailable(reason: .modelNotReady)
        )
        let sut = AppState(cardAuthor: mock)
        let resolvedText = "Offline captured text"

        await sut.enqueue(resolvedText: resolvedText)

        let presented = try #require(sut.presentedDraft)
        #expect(presented.draft.question == resolvedText)
        #expect(presented.draft.answer == "")
    }

    // MARK: enqueue_preservesQueueOrder_acrossMultipleDrains

    @Test("enqueue preserves FIFO order across multiple calls")
    func enqueue_preservesQueueOrder_acrossMultipleDrains() async throws {
        // Each call to author() returns the configured draft. We enqueue three items
        // and verify they surface in insertion order as the user accepts each one.
        let d1 = CardDraft(question: "Q1", answer: "A1")
        let d2 = CardDraft(question: "Q2", answer: "A2")
        let d3 = CardDraft(question: "Q3", answer: "A3")

        // Three separate mock instances so each enqueue call gets a distinct draft.
        let sut = AppState(cardAuthor: MockCardAuthoringService(drafts: [d1]))
        // Enqueue three items — we swap mock via the drainer bridge in production;
        // for ordering purposes all we need is that Codex's implementation calls
        // author() once per enqueue and appends in order.
        await sut.enqueue(resolvedText: "text1")  // → d1 (presentedDraft set immediately)

        // For the remaining items we can't easily swap the mock, so use two more
        // sut instances to verify each individually, then rely on the ordering test
        // below that drives acceptDraft() through the queue.
        let sut2 = AppState(cardAuthor: MockCardAuthoringService(drafts: [d1, d2, d3]))
        await sut2.enqueue(resolvedText: "text1")
        await sut2.enqueue(resolvedText: "text2")
        await sut2.enqueue(resolvedText: "text3")

        // After 3 enqueues: first draft is presentedDraft, two remain in queue.
        let first = try #require(sut2.presentedDraft)
        #expect(first.draft.question == "Q1")

        sut2.acceptDraft()
        let second = try #require(sut2.presentedDraft)
        #expect(second.draft.question == "Q2")  // fails with stub (stub uses resolvedText as question)

        sut2.acceptDraft()
        let third = try #require(sut2.presentedDraft)
        #expect(third.draft.question == "Q3")
    }

    // MARK: acceptDraft_persistsCardToStore

    @Test("acceptDraft persists the accepted draft to cardStore")
    func acceptDraft_persistsCardToStore() async throws {
        let draft = CardDraft(question: "What is 2+2?", answer: "4")
        let mockAuthor = MockCardAuthoringService(drafts: [draft])
        let mockStore = MockCardStore()
        let sut = AppState(cardAuthor: mockAuthor, cardStore: mockStore)

        await sut.enqueue(resolvedText: "2+2=4")
        _ = try #require(sut.presentedDraft)

        sut.acceptDraft()

        // Yield so the Task inside acceptDraft has a chance to run.
        await Task.yield()
        await Task.yield()

        #expect(mockStore.cards.count == 1)
        #expect(mockStore.cards.first?.question == "What is 2+2?")
        #expect(mockStore.cards.first?.answer == "4")
        #expect(sut.presentedDraft == nil)
    }

    // MARK: enqueueFallbackPreservesCapturedTextAsQuestion (M9)

    @Test("enqueue preserves captured text as question when authoring fails")
    func enqueueFallbackPreservesCapturedTextAsQuestion() async throws {
        let state = AppState(cardAuthor: FailingAuthor(), cardStore: MockCardStore())
        await state.enqueue(resolvedText: "Mitochondria is the powerhouse of the cell")
        let presented = try #require(state.presentedDraft)
        #expect(presented.draft.question == "Mitochondria is the powerhouse of the cell")
        #expect(presented.draft.answer.isEmpty == true)
    }
}
