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

    // MARK: isFallback marking (#30)
    //
    // `CaptureAvailabilityBanner`/`CardReviewSheet` need to distinguish a
    // real AI-authored draft from the stub `appendFallbackDraft` queues when
    // authoring produced nothing, so the review sheet can tell the user "AI
    // unavailable — edit this card by hand" instead of presenting a stub as
    // if it were AI-authored.

    @Test("a fallback draft queued after a zero-yield stream is marked isFallback")
    func enqueue_zeroYieldFallback_marksIsFallback() async throws {
        let sut = AppState(cardAuthor: EmptyStreamAuthor())

        await sut.enqueue(resolvedText: "Text the model produced nothing for")

        let presented = try #require(sut.presentedDraft)
        #expect(presented.isFallback == true)
    }

    @Test("a fallback draft queued after a pre-yield throw is marked isFallback")
    func enqueue_preYieldThrowFallback_marksIsFallback() async throws {
        let sut = AppState(cardAuthor: FailingAuthor())

        await sut.enqueue(resolvedText: "Some captured text")

        let presented = try #require(sut.presentedDraft)
        #expect(presented.isFallback == true)
    }

    @Test("a real AI-authored draft from a streaming author is not marked isFallback")
    func enqueue_realStreamedDraft_isNotFallback() async throws {
        let expected = CardDraft(question: "What is the capital of France?", answer: "Paris")
        let sut = AppState(cardAuthor: MockCardAuthoringService(drafts: [expected]))

        await sut.enqueue(resolvedText: "France's capital is Paris.")

        let presented = try #require(sut.presentedDraft)
        #expect(presented.isFallback == false)
    }
}

// MARK: - #34 authoringCount (drafting indicator)
//
// Between a capture and the draft sheet appearing, `enqueue(resolvedText:)`
// awaits on-device generation with no visible feedback. `authoringCount`
// tracks the number of `enqueue` calls currently in flight so `ContentView`
// can show a drafting indicator while it's non-zero. It's an `Int` rather
// than a `Bool` so it stays accurate under concurrent captures.

/// Routes to a distinct `(drafts, gate)` pair per `resolvedText`, letting a
/// test suspend two concurrent `enqueue` calls independently. Sharing a
/// single `GatedStreamAuthor`'s one `StreamGate` between two callers would
/// corrupt the gate's single-continuation slot (its `wait()` overwrites
/// `continuation` on a second concurrent caller, stranding the first).
/// Mirrors `GatedStreamAuthor`'s body, keyed by input text instead of fixed.
private struct RoutingGatedStreamAuthor: CardAuthoringService {
    let routes: [String: (drafts: [CardDraft], gate: StreamGate)]

    var availability: AuthoringAvailability {
        get async { .available }
    }

    func generateDrafts(from text: String) async throws -> AsyncThrowingStream<CardDraft, Error> {
        guard let route = routes[text] else {
            return AsyncThrowingStream { continuation in continuation.finish() }
        }
        let drafts = route.drafts
        let gate = route.gate
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

@Suite("AppState.authoringCount — #34 drafting indicator")
@MainActor
struct AppStateAuthoringCountTests {

    /// Cooperatively yields the MainActor until `condition` holds, bounded so
    /// a genuine regression fails fast instead of hanging. Mirrors the helper
    /// in `AppStateEnqueueTests`.
    private func waitUntil(
        maxIterations: Int = 10_000,
        _ condition: () -> Bool
    ) async {
        for _ in 0..<maxIterations {
            if condition() { return }
            await Task.yield()
        }
    }

    // MARK: authoringCount_risesAndFalls_aroundASingleEnqueue

    @Test("authoringCount is 0 at rest, rises to 1 while a gated enqueue is suspended mid-stream, and returns to 0 once the stream completes")
    func authoringCount_risesAndFalls_aroundASingleEnqueue() async throws {
        let d1 = CardDraft(question: "Q1", answer: "A1")
        let gate = StreamGate()
        let sut = AppState(cardAuthor: GatedStreamAuthor(drafts: [d1], gate: gate))

        #expect(sut.authoringCount == 0)

        let task = Task { @MainActor in
            await sut.enqueue(resolvedText: "capture")
        }

        // Registration barrier: don't assert until enqueue has actually
        // incremented the count, proving it's suspended mid-stream (parked
        // at the gate after yielding the first draft) rather than merely not
        // yet scheduled.
        await waitUntil { sut.authoringCount == 1 }
        #expect(sut.authoringCount == 1)

        gate.release()
        await task.value

        #expect(sut.authoringCount == 0)
    }

    // MARK: authoringCount_tracksConcurrentEnqueues

    @Test("two concurrent gated enqueues both count: authoringCount is 2 while both are suspended, and drops back to 0 only after both finish")
    func authoringCount_tracksConcurrentEnqueues() async throws {
        let a1 = CardDraft(question: "A1", answer: "a1")
        let b1 = CardDraft(question: "B1", answer: "b1")
        let gateA = StreamGate()
        let gateB = StreamGate()
        let sut = AppState(cardAuthor: RoutingGatedStreamAuthor(routes: [
            "capture A": (drafts: [a1], gate: gateA),
            "capture B": (drafts: [b1], gate: gateB),
        ]))

        #expect(sut.authoringCount == 0)

        let taskA = Task { @MainActor in await sut.enqueue(resolvedText: "capture A") }
        let taskB = Task { @MainActor in await sut.enqueue(resolvedText: "capture B") }

        await waitUntil { sut.authoringCount == 2 }
        #expect(sut.authoringCount == 2)

        gateA.release()
        await taskA.value
        #expect(sut.authoringCount == 1)

        gateB.release()
        await taskB.value
        #expect(sut.authoringCount == 0)
    }

    // MARK: authoringCount_returnsToZero_afterPreYieldThrow

    @Test("authoringCount returns to 0 even when the author throws before yielding anything — the defer guard fires on a thrown stream too")
    func authoringCount_returnsToZero_afterPreYieldThrow() async throws {
        let sut = AppState(cardAuthor: FailingAuthor())

        await sut.enqueue(resolvedText: "some captured text")

        #expect(sut.authoringCount == 0)
    }
}

// MARK: - #30 authoring availability caching

@Suite("AppState.refreshAuthoringAvailability — #30 capture-tab banner")
@MainActor
struct AppStateAuthoringAvailabilityTests {

    @Test("authoringAvailability is nil until refreshAuthoringAvailability has run")
    func authoringAvailability_isNilBeforeFirstRefresh() async throws {
        let sut = AppState(cardAuthor: MockCardAuthoringService(availability: .available))
        #expect(sut.authoringAvailability == nil)
    }

    @Test("refreshAuthoringAvailability caches the cardAuthor's current availability")
    func refreshAuthoringAvailability_setsFromCardAuthor() async throws {
        let mock = MockCardAuthoringService(availability: .unavailable(reason: .deviceNotEligible))
        let sut = AppState(cardAuthor: mock)

        await sut.refreshAuthoringAvailability()

        #expect(sut.authoringAvailability == .unavailable(reason: .deviceNotEligible))
    }

    @Test("refreshAuthoringAvailability reflects .available when the model is ready")
    func refreshAuthoringAvailability_reflectsAvailable() async throws {
        let sut = AppState(cardAuthor: MockCardAuthoringService(availability: .available))

        await sut.refreshAuthoringAvailability()

        #expect(sut.authoringAvailability == .available)
    }
}

// MARK: - #32 handleSheetDismiss (interactive swipe-dismiss must advance the queue)
//
// The draft sheet is `.sheet(item: $appState.presentedDraft, onDismiss: ...)`.
// An interactive swipe-down sets `presentedDraft = nil` without going through
// `advanceQueue()`, stranding any remaining `pendingDrafts` invisibly until a
// new capture calls `enqueue`. `handleSheetDismiss()` fixes this with a
// purely state-based, idempotent rule: advance only when `presentedDraft` is
// already `nil` at the moment `onDismiss` fires. A button (Accept/Skip) calls
// `advanceQueue()` itself before the sheet ever dismisses, so by the time
// `onDismiss` runs `presentedDraft` is already non-nil (next draft) or nil
// (queue emptied) — either way, re-advancing here would double-advance or
// drop a draft. A swipe never calls `advanceQueue()`, so `presentedDraft` is
// still nil at `onDismiss` time, and this is the only path that needs to
// advance.
/// Controllable suspension point standing in for the `CardStore` actor's
/// genuine cross-actor hop on `create(...)`. `MockCardStore` is a plain
/// class, so without this its `create(...)` never truly suspends and the
/// in-flight-persist race #32's rule must survive can't be reproduced
/// deterministically. Mirrors the `AwaitGate` idiom in
/// `AppStateAcceptDraftReentrancyTests` (file-private, so no collision).
@MainActor
private final class AwaitGate: @unchecked Sendable {
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

@Suite("AppState.handleSheetDismiss — #32 swipe-dismiss advances the queue")
@MainActor
struct AppStateSheetDismissTests {

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

    // MARK: swipeDismiss_advancesToNextDraft_onePerSwipe

    @Test("an interactive swipe-dismiss advances to the next pending draft, exactly once per swipe")
    func swipeDismiss_advancesToNextDraft_onePerSwipe() async throws {
        let a = CardDraft(question: "A", answer: "a")
        let b = CardDraft(question: "B", answer: "b")
        let c = CardDraft(question: "C", answer: "c")
        let sut = AppState(cardAuthor: MockCardAuthoringService(drafts: [a, b, c]))

        await sut.enqueue(resolvedText: "one dense paragraph")
        #expect(sut.presentedDraft?.draft.question == "A")

        // Simulate SwiftUI's interactive swipe: it clears the binding first,
        // then fires onDismiss.
        sut.presentedDraft = nil
        sut.handleSheetDismiss()
        #expect(sut.presentedDraft?.draft.question == "B")

        sut.presentedDraft = nil
        sut.handleSheetDismiss()
        #expect(sut.presentedDraft?.draft.question == "C")

        sut.presentedDraft = nil
        sut.handleSheetDismiss()
        #expect(sut.presentedDraft == nil)
    }

    // MARK: buttonDismiss_doesNotDoubleAdvance

    @Test("a button-driven dismiss does not double-advance when onDismiss fires on an item-to-item change")
    func buttonDismiss_doesNotDoubleAdvance() async throws {
        let a = CardDraft(question: "A", answer: "a")
        let b = CardDraft(question: "B", answer: "b")
        let c = CardDraft(question: "C", answer: "c")
        let mockStore = MockCardStore()
        let sut = AppState(cardAuthor: MockCardAuthoringService(drafts: [a, b, c]), cardStore: mockStore)

        await sut.enqueue(resolvedText: "one dense paragraph")
        await sut.acceptDraft() // advanceQueue() already ran: presentedDraft == B
        #expect(sut.presentedDraft?.draft.question == "B")

        // Simulate SwiftUI firing onDismiss on an item->item change, WITHOUT
        // clearing presentedDraft first (unlike the swipe path above).
        sut.handleSheetDismiss()

        // No-op: still B, C still pending behind it.
        #expect(sut.presentedDraft?.draft.question == "B")
        await sut.acceptDraft()
        #expect(sut.presentedDraft?.draft.question == "C")
    }

    // MARK: lastCardButtonDismiss_isHarmlessNoOp

    @Test("dismiss after the last card's button-accept is a harmless no-op — no duplicate persist")
    func lastCardButtonDismiss_isHarmlessNoOp() async throws {
        let a = CardDraft(question: "A", answer: "a")
        let mockStore = MockCardStore()
        let sut = AppState(cardAuthor: MockCardAuthoringService(drafts: [a]), cardStore: mockStore)

        await sut.enqueue(resolvedText: "single draft capture")
        await sut.acceptDraft() // advanceQueue() emptied the queue: presentedDraft == nil
        #expect(sut.presentedDraft == nil)
        #expect(mockStore.cards.count == 1)

        // onDismiss now fires for the sheet's teardown. presentedDraft is
        // already nil, so this looks identical to a swipe — but
        // advanceQueue() on an empty queue is itself a harmless no-op.
        sut.handleSheetDismiss()

        #expect(sut.presentedDraft == nil)
        #expect(mockStore.cards.count == 1)
    }

    // MARK: mixedSequence_acceptSwipeAccept_persistsExactlyAcceptedDrafts

    @Test("a mixed accept/swipe/accept sequence persists exactly the accepted drafts, with no drops or duplicates")
    func mixedSequence_acceptSwipeAccept_persistsExactlyAcceptedDrafts() async throws {
        let a = CardDraft(question: "A", answer: "a")
        let b = CardDraft(question: "B", answer: "b")
        let c = CardDraft(question: "C", answer: "c")
        let mockStore = MockCardStore()
        let sut = AppState(cardAuthor: MockCardAuthoringService(drafts: [a, b, c]), cardStore: mockStore)

        await sut.enqueue(resolvedText: "one dense paragraph")
        #expect(sut.presentedDraft?.draft.question == "A")

        await sut.acceptDraft() // accept A -> B
        #expect(sut.presentedDraft?.draft.question == "B")

        // Swipe away B (skipped, never persisted).
        sut.presentedDraft = nil
        sut.handleSheetDismiss()
        #expect(sut.presentedDraft?.draft.question == "C")

        await sut.acceptDraft() // accept C -> nil
        #expect(sut.presentedDraft == nil)

        #expect(mockStore.cards.count == 2)
        #expect(mockStore.cards.map(\.question) == ["A", "C"])
    }

    // MARK: swipeDuringInFlightPersist_advancesOnce_withoutDropOrDuplicate
    //
    // The other four cases hand-order calls; this one pins the repo's known
    // hotspot — a post-`await` state bug — with a *genuine* async suspension.
    // A's persist is held open mid-`create(...)` while the user swipes the
    // next draft away. The state-based rule must still advance exactly once
    // and must not double-advance or drop/duplicate a draft when `onDismiss`
    // races an accept that's already suspended past its synchronous advance.

    @Test("a swipe landing while a prior accept's persist is still suspended advances exactly once, dropping/duplicating nothing")
    func swipeDuringInFlightPersist_advancesOnce_withoutDropOrDuplicate() async throws {
        let a = CardDraft(question: "A", answer: "a")
        let b = CardDraft(question: "B", answer: "b")
        let c = CardDraft(question: "C", answer: "c")
        let mockStore = MockCardStore()
        let gate = AwaitGate()
        let sut = AppState(cardAuthor: MockCardAuthoringService(drafts: [a, b, c]), cardStore: mockStore)

        await sut.enqueue(resolvedText: "one dense paragraph")
        #expect(sut.presentedDraft?.draft.question == "A")

        // Suspend acceptDraft's persist so A stays genuinely in flight.
        mockStore.createGate = { await gate.wait() }

        // Accept A: advanceQueue() runs synchronously (A -> B) *before* the
        // persist of A suspends on the gate.
        let acceptTask = Task { @MainActor in
            await sut.acceptDraft()
        }

        // Registration barrier: the synchronous advance A -> B has happened
        // and A's persist is genuinely parked inside cardStore.create.
        await waitUntil { sut.presentedDraft?.draft.question == "B" && gate.callCount >= 1 }

        // While A's create is still suspended, the user swipes B away —
        // onDismiss fires with a persist still in flight. `presentedDraft`
        // is nil here (swipe cleared it), so the rule advances exactly once.
        sut.presentedDraft = nil
        sut.handleSheetDismiss()
        #expect(sut.presentedDraft?.draft.question == "C")

        // Let A's persist complete and the accept task finish.
        gate.fireOldest()
        await acceptTask.value

        // A (and only A) was persisted; C is still presented; the swipe
        // racing the in-flight accept dropped/duplicated nothing and did not
        // double-advance past C.
        #expect(mockStore.cards.count == 1)
        #expect(mockStore.cards.first?.question == "A")
        #expect(sut.presentedDraft?.draft.question == "C")
    }
}

// MARK: - Epic #10 checkpoint hardening (#32 × #29 batchCounts leak on swipe)
//
// GPT-5.5's Epic #10 cross-issue checkpoint found that swiping away the LAST
// card of a batch leaked its `batchCounts` entry: SwiftUI nils `presentedDraft`
// before `handleSheetDismiss()` calls `advanceQueue()`, so the old per-id prune
// had no "previous" batch to target. `pruneStaleBatchCounts()` (full sweep)
// fixes it. These pin the invariant "batchCounts returns to empty once every
// draft from a batch has left the queue" across the swipe paths.
@Suite("AppState batchCounts — swipe-dismiss leak (Epic #10 checkpoint)")
@MainActor
struct AppStateBatchCountSwipeTests {

    @Test("swiping away a single-draft batch prunes its batchCounts entry")
    func swipeSingletonBatch_prunesBatchCounts() async throws {
        let sut = AppState(cardAuthor: MockCardAuthoringService(drafts: [CardDraft(question: "Q1", answer: "A1")]))
        await sut.enqueue(resolvedText: "one")
        #expect(sut.batchCountEntryCount == 1)

        // Interactive swipe: SwiftUI clears the binding, then onDismiss fires.
        sut.presentedDraft = nil
        sut.handleSheetDismiss()

        #expect(sut.presentedDraft == nil)
        #expect(sut.batchCountEntryCount == 0)
    }

    @Test("swiping away the LAST card of a multi-draft batch prunes its batchCounts entry")
    func swipeLastCardOfBatch_prunesBatchCounts() async throws {
        let d1 = CardDraft(question: "Q1", answer: "A1")
        let d2 = CardDraft(question: "Q2", answer: "A2")
        let sut = AppState(cardAuthor: MockCardAuthoringService(drafts: [d1, d2]))
        await sut.enqueue(resolvedText: "two")
        #expect(sut.batchCountEntryCount == 1)

        // Swipe the first card → advances to the second (batch still live).
        sut.presentedDraft = nil
        sut.handleSheetDismiss()
        #expect(sut.presentedDraft?.draft.question == "Q2")
        #expect(sut.batchCountEntryCount == 1)

        // Swipe the last card → batch is now gone everywhere; entry pruned.
        sut.presentedDraft = nil
        sut.handleSheetDismiss()
        #expect(sut.presentedDraft == nil)
        #expect(sut.batchCountEntryCount == 0)
    }
}
