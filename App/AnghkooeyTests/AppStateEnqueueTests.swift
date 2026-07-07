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

// MARK: - #29 multi-draft enqueue stubs

/// Stream that completes successfully without ever yielding a draft —
/// simulates the model producing nothing for the given input.
private struct EmptyStreamAuthor: CardAuthoringService {
    var availability: AuthoringAvailability {
        get async { .available }
    }

    func generateDrafts(from text: String) async throws -> AsyncThrowingStream<CardDraft, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}

/// Stream that yields one draft and then fails — simulates a capture that
/// produced partial results before the model errored out mid-generation.
private struct PartialThenFailingAuthor: CardAuthoringService {
    let draft: CardDraft

    var availability: AuthoringAvailability {
        get async { .available }
    }

    func generateDrafts(from text: String) async throws -> AsyncThrowingStream<CardDraft, Error> {
        let draft = self.draft
        return AsyncThrowingStream { continuation in
            continuation.yield(draft)
            continuation.finish(throwing: AuthoringError.generationFailed(underlying: URLError(.timedOut)))
        }
    }
}

/// Returns a distinct fixture per `resolvedText`, so a single `AppState`
/// (which holds one injected `cardAuthor`) can drive two genuinely different
/// captures — required to prove `presentedDraftProgress` stays batch-local
/// when captures interleave (#29).
private struct RoutingAuthor: CardAuthoringService {
    let routes: [String: [CardDraft]]

    var availability: AuthoringAvailability {
        get async { .available }
    }

    func generateDrafts(from text: String) async throws -> AsyncThrowingStream<CardDraft, Error> {
        let drafts = routes[text] ?? []
        return AsyncThrowingStream { continuation in
            for draft in drafts { continuation.yield(draft) }
            continuation.finish()
        }
    }
}

/// Order-independent one-shot gate for the "first sheet before the stream
/// finishes" test. `release()` before any `wait()` is honored (a later
/// `wait()` returns immediately), so the test never deadlocks on producer /
/// consumer scheduling order — the flake this repo's continuation tests hit
/// without a registration barrier.
@MainActor
private final class StreamGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false

    func wait() async {
        if released { return }
        await withCheckedContinuation { c in
            if released { c.resume() } else { continuation = c }
        }
    }

    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}

/// Yields the first draft, parks on `gate`, then yields the rest and
/// finishes. Lets a test observe `presentedDraft`/`presentedDraftProgress`
/// while the stream is still mid-flight (proving `enqueue` presents the
/// first draft without waiting for the stream to complete).
private struct GatedStreamAuthor: CardAuthoringService {
    let drafts: [CardDraft]
    let gate: StreamGate

    var availability: AuthoringAvailability {
        get async { .available }
    }

    func generateDrafts(from text: String) async throws -> AsyncThrowingStream<CardDraft, Error> {
        let drafts = self.drafts
        let gate = self.gate
        return AsyncThrowingStream { continuation in
            let task = Task {
                guard let first = drafts.first else {
                    continuation.finish()
                    return
                }
                continuation.yield(first)
                await gate.wait()
                for draft in drafts.dropFirst() { continuation.yield(draft) }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

@Suite("AppState.enqueue — M4.2 contract")
@MainActor
struct AppStateEnqueueTests {

    /// Cooperatively yields the MainActor until `condition` holds, bounded so
    /// a genuine regression fails fast instead of hanging. Mirrors the helper
    /// in `AppStateAcceptDraftReentrancyTests`.
    private func waitUntil(
        maxIterations: Int = 10_000,
        _ condition: () -> Bool
    ) async {
        for _ in 0..<maxIterations {
            if condition() { return }
            await Task.yield()
        }
    }

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

    // MARK: enqueue_singleCaptureYieldingMultipleDrafts_queuesAllInOrder
    //
    // Replaces the old `enqueue_preservesQueueOrder_acrossMultipleDrains`,
    // which drove three separate `enqueue` calls each yielding one draft.
    // Under the #29 fix a single `enqueue` call fully drains
    // `generateDrafts(from:)`, so a dense capture that authors 3 drafts must
    // queue all 3 from ONE call, not 9 across three calls.

    @Test("a single enqueue call queues every draft the stream yields, in order")
    func enqueue_singleCaptureYieldingMultipleDrafts_queuesAllInOrder() async throws {
        let d1 = CardDraft(question: "Q1", answer: "A1")
        let d2 = CardDraft(question: "Q2", answer: "A2")
        let d3 = CardDraft(question: "Q3", answer: "A3")
        let sut = AppState(cardAuthor: MockCardAuthoringService(drafts: [d1, d2, d3]))

        await sut.enqueue(resolvedText: "one dense paragraph")

        // The first draft is presented as soon as the stream yields it, not
        // after the whole stream drains.
        let first = try #require(sut.presentedDraft)
        #expect(first.draft.question == "Q1")

        await sut.acceptDraft()
        let second = try #require(sut.presentedDraft)
        #expect(second.draft.question == "Q2")

        await sut.acceptDraft()
        let third = try #require(sut.presentedDraft)
        #expect(third.draft.question == "Q3")

        await sut.acceptDraft()
        #expect(sut.presentedDraft == nil)
    }

    // MARK: enqueue_presentedDraftProgress_reflectsBatchPositionAndTotal

    @Test("presentedDraftProgress reports this draft's position within its own capture's batch")
    func enqueue_presentedDraftProgress_reflectsBatchPositionAndTotal() async throws {
        let d1 = CardDraft(question: "Q1", answer: "A1")
        let d2 = CardDraft(question: "Q2", answer: "A2")
        let d3 = CardDraft(question: "Q3", answer: "A3")
        let sut = AppState(cardAuthor: MockCardAuthoringService(drafts: [d1, d2, d3]))

        await sut.enqueue(resolvedText: "one dense paragraph")

        let firstProgress = try #require(sut.presentedDraftProgress)
        #expect(firstProgress.position == 1)
        #expect(firstProgress.total == 3)

        await sut.acceptDraft()
        let secondProgress = try #require(sut.presentedDraftProgress)
        #expect(secondProgress.position == 2)
        #expect(secondProgress.total == 3)
    }

    // MARK: enqueue_zeroYieldSuccess_fallsBackToStub

    @Test("enqueue falls back to a stub draft when the stream completes without yielding any draft")
    func enqueue_zeroYieldSuccess_fallsBackToStub() async throws {
        let sut = AppState(cardAuthor: EmptyStreamAuthor())
        let resolvedText = "Text the model produced nothing for"

        await sut.enqueue(resolvedText: resolvedText)

        let presented = try #require(sut.presentedDraft)
        #expect(presented.draft.question == resolvedText)
        #expect(presented.draft.answer == "")
        // Exactly one fallback stub, not one per yield (there were none).
        await sut.acceptDraft()
        #expect(sut.presentedDraft == nil)
    }

    // MARK: enqueue_someDraftsThenError_keepsArrivedDraftsWithoutAppendingStub

    @Test("enqueue keeps drafts that already arrived when the stream fails partway, without appending a fallback stub")
    func enqueue_someDraftsThenError_keepsArrivedDraftsWithoutAppendingStub() async throws {
        let d1 = CardDraft(question: "Q1", answer: "A1")
        let sut = AppState(cardAuthor: PartialThenFailingAuthor(draft: d1))

        await sut.enqueue(resolvedText: "partially generated capture")

        let presented = try #require(sut.presentedDraft)
        #expect(presented.draft.question == "Q1")
        #expect(presented.draft.answer == "A1")

        // No extra stub was appended: accepting the one arrived draft empties
        // the queue immediately.
        await sut.acceptDraft()
        #expect(sut.presentedDraft == nil)
    }

    // MARK: enqueue_presentedDraftProgress_isBatchLocal_whenCapturesInterleave

    @Test("presentedDraftProgress reports only the presented draft's own batch total, not the global queue depth, when captures interleave")
    func enqueue_presentedDraftProgress_isBatchLocal_whenCapturesInterleave() async throws {
        let a1 = CardDraft(question: "A1", answer: "a1")
        let a2 = CardDraft(question: "A2", answer: "a2")
        let b1 = CardDraft(question: "B1", answer: "b1")
        let b2 = CardDraft(question: "B2", answer: "b2")
        let b3 = CardDraft(question: "B3", answer: "b3")
        let sut = AppState(cardAuthor: RoutingAuthor(routes: [
            "capture A": [a1, a2],
            "capture B": [b1, b2, b3],
        ]))

        // Capture A: a1 presented, a2 pending.
        await sut.enqueue(resolvedText: "capture A")
        // Capture B arrives before A is accepted: b1/b2/b3 pile into
        // pendingDrafts behind a2 while a1 is still on screen.
        await sut.enqueue(resolvedText: "capture B")

        // The global count (presented + pendingDrafts.count) would say "1 of
        // 4" here — B's three drafts inflate it. Batch-local progress must
        // report A's own total instead.
        let aProgress = try #require(sut.presentedDraftProgress)
        #expect(aProgress.position == 1)
        #expect(aProgress.total == 2)

        await sut.acceptDraft()
        let a2Progress = try #require(sut.presentedDraftProgress)
        #expect(a2Progress.position == 2)
        #expect(a2Progress.total == 2)

        // Accepting through A surfaces B, which reports its own (1, 3).
        await sut.acceptDraft()
        let bProgress = try #require(sut.presentedDraftProgress)
        #expect(sut.presentedDraft?.draft.question == "B1")
        #expect(bProgress.position == 1)
        #expect(bProgress.total == 3)
    }

    // MARK: enqueue_presentsFirstDraftBeforeStreamCompletes

    @Test("enqueue presents the first draft while the stream is still yielding the rest")
    func enqueue_presentsFirstDraftBeforeStreamCompletes() async throws {
        let d1 = CardDraft(question: "Q1", answer: "A1")
        let d2 = CardDraft(question: "Q2", answer: "A2")
        let d3 = CardDraft(question: "Q3", answer: "A3")
        let gate = StreamGate()
        let sut = AppState(cardAuthor: GatedStreamAuthor(drafts: [d1, d2, d3], gate: gate))

        // Drive enqueue concurrently so the test can observe mid-stream state
        // while the producer is parked at the gate.
        let task = Task { @MainActor in
            await sut.enqueue(resolvedText: "dense capture")
        }

        // Registration barrier: don't assert until the first draft is
        // actually presented (proving enqueue got past the first yield and is
        // now parked awaiting more), which also guarantees the producer has
        // reached the gate.
        await waitUntil { sut.presentedDraft != nil }

        let presented = try #require(sut.presentedDraft)
        #expect(presented.draft.question == "Q1")
        // Only the first draft has streamed in — total must not pre-count the
        // still-suspended d2/d3.
        #expect(sut.presentedDraftProgress?.total == 1)

        // Release the rest of the stream and let enqueue finish.
        gate.release()
        await task.value

        // All three are now queued; total reflects the full batch.
        #expect(sut.presentedDraftProgress?.total == 3)
        await sut.acceptDraft()
        #expect(sut.presentedDraft?.draft.question == "Q2")
        await sut.acceptDraft()
        #expect(sut.presentedDraft?.draft.question == "Q3")
        await sut.acceptDraft()
        #expect(sut.presentedDraft == nil)
    }

    // MARK: enqueue_softCap_limitsBatchToTenDrafts

    @Test("enqueue caps a single capture at 10 drafts and discards the rest")
    func enqueue_softCap_limitsBatchToTenDrafts() async throws {
        let drafts = (1...15).map { CardDraft(question: "Q\($0)", answer: "A\($0)") }
        let sut = AppState(cardAuthor: MockCardAuthoringService(drafts: drafts))

        await sut.enqueue(resolvedText: "an extremely dense capture")

        // total caps at 10 immediately, not 15.
        #expect(sut.presentedDraftProgress?.total == 10)

        // Exactly 10 surface, in order; the 11th accept clears the queue.
        for i in 1...10 {
            let presented = try #require(sut.presentedDraft)
            #expect(presented.draft.question == "Q\(i)")
            await sut.acceptDraft()
        }
        #expect(sut.presentedDraft == nil)
    }

    // MARK: batchCounts_prunesToEmpty_afterFullBatchAccepted

    @Test("batchCounts returns to empty once a fully-streamed batch is accepted through")
    func batchCounts_prunesToEmpty_afterFullBatchAccepted() async throws {
        let d1 = CardDraft(question: "Q1", answer: "A1")
        let d2 = CardDraft(question: "Q2", answer: "A2")
        let sut = AppState(cardAuthor: MockCardAuthoringService(drafts: [d1, d2]))

        await sut.enqueue(resolvedText: "batch")
        #expect(sut.batchCountEntryCount == 1)

        await sut.acceptDraft()          // d1 accepted, d2 still presented
        #expect(sut.batchCountEntryCount == 1)

        await sut.acceptDraft()          // d2 accepted, batch fully drained
        #expect(sut.presentedDraft == nil)
        #expect(sut.batchCountEntryCount == 0)
    }

    // MARK: batchCounts_noLeak_throughRetryRemovePath

    @Test("batchCounts does not leak an entry when a failed accept is retried via the remove-from-pending path")
    func batchCounts_noLeak_throughRetryRemovePath() async throws {
        let a1 = CardDraft(question: "A1", answer: "a1")
        let b1 = CardDraft(question: "B1", answer: "b1")
        let mockStore = MockCardStore()
        let sut = AppState(
            cardAuthor: RoutingAuthor(routes: ["A": [a1], "B": [b1]]),
            cardStore: mockStore
        )

        await sut.enqueue(resolvedText: "A")   // a1 presented
        await sut.enqueue(resolvedText: "B")   // b1 pending behind a1
        #expect(sut.batchCountEntryCount == 2)

        // Fail a1's accept: a1 is re-parked in pendingDrafts while b1 becomes
        // the presented draft. The stale retry closure now targets a1, which
        // is NOT the presented draft — so retrying takes the
        // remove-from-pending (`else`) branch of retryAcceptDraft.
        mockStore.createError = PersistenceError.containerCreationFailed(
            underlying: NSError(domain: "test", code: 1))
        await sut.acceptDraft()
        #expect(sut.presentedDraft?.draft.question == "B1")
        #expect(sut.errorPresenter.toast != nil)

        // Retry succeeds and drives the remove-from-pending branch.
        mockStore.createError = nil
        await sut.errorPresenter.retry()
        #expect(mockStore.cards.contains { $0.question == "A1" })

        // Accept the remaining presented draft; the queue is now empty and
        // batchCounts must be back to zero — no stale entry left behind by
        // the remove-from-pending path.
        await sut.acceptDraft()
        #expect(sut.presentedDraft == nil)
        #expect(sut.batchCountEntryCount == 0)
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

        // acceptDraft is async and only returns once the create has landed —
        // a single await suffices, no bounded-poll de-flake needed (#20).
        await sut.acceptDraft()

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
