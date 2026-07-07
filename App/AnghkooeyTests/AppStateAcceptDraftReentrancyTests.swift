import Testing
import Foundation
@testable import Anghkooey
import AnghkooeyCore
import AnghkooeyIntelligence
import AnghkooeyUI

// MARK: - epic8 regression coverage
//
// `AnghkooeyApp` wraps the Accept button's `onAccept` in
// `Task { await appState.acceptDraft(...) }`, so `acceptDraft` resolves
// `presentedDraft` at *task-run* time, not tap time. A rapid double-tap on
// the same sheet enqueues two such Tasks carrying the same (soon-to-be-stale)
// question/answer text. Before the fix, if the first task was still
// suspended mid-persist when the second task started, the second task would
// read `presentedDraft` as whatever the first task had already advanced to
// (draft 2) and persist *that* draft using the first tap's text for draft 1
// — silently corrupting draft 2's content. This suite pins the reentrancy
// guard that makes the second, overlapping call a no-op instead.

/// Controllable suspension point standing in for the real `CardStore`
/// actor's genuine cross-actor hop on every `create(...)` call.
/// `MockCardStore` is a plain class, not an actor, so without this its
/// `create(...)` never truly suspends — two `acceptDraft` Tasks would run
/// fully sequentially (the first completing entirely before the second's
/// Task is even scheduled), and the reentrancy race this suite exists to
/// catch could never be reproduced deterministically. Mirrors the
/// `SleepGate` pattern used in `ReviewSessionRequeueTests`/`ErrorPresenterTests`.
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

@Suite("AppState.acceptDraft — epic8 reentrancy guard")
@MainActor
struct AppStateAcceptDraftReentrancyTests {

    /// Waits for `condition` to become true by cooperatively yielding the
    /// MainActor. Bounded so a genuine regression fails fast instead of
    /// hanging. Mirrors `ReviewSessionRequeueTests`.
    private func waitUntil(
        maxIterations: Int = 10_000,
        _ condition: () -> Bool
    ) async {
        for _ in 0..<maxIterations {
            if condition() { return }
            await Task.yield()
        }
    }

    @Test("a second acceptDraft call that overlaps the first's in-flight persist is a no-op: only the first draft is created, the second stays presented")
    func overlappingAcceptDraftDoesNotCorruptTheSecondDraft() async throws {
        let d1 = CardDraft(question: "Q1", answer: "A1")
        let d2 = CardDraft(question: "Q2", answer: "A2")
        let mockStore = MockCardStore()
        let gate = AwaitGate()
        let sut = AppState(cardAuthor: MockCardAuthoringService(drafts: [d1, d2]), cardStore: mockStore)

        // A single capture whose stream yields both drafts (#29: enqueue now
        // fully drains generateDrafts(from:), so one call queues both).
        await sut.enqueue(resolvedText: "text1")
        let first = try #require(sut.presentedDraft)
        #expect(first.draft.question == "Q1")

        mockStore.createGate = { await gate.wait() }

        // Tap 1: accepts draft 1 with its own (correct) text.
        let taskA = Task { @MainActor in
            await sut.acceptDraft(question: "Q1", answer: "A1")
        }

        // Confirm task A is genuinely suspended inside `cardStore.create`
        // before task B is ever spawned — `acceptDraft` advances the queue
        // synchronously before this point, so `presentedDraft` is already
        // draft 2 by the time we observe the gate.
        await waitUntil { gate.callCount >= 1 }
        let advanced = try #require(sut.presentedDraft)
        #expect(advanced.draft.question == "Q2")

        // Tap 2: a rapid double-tap firing while task A's Task is still
        // in flight, carrying draft 1's stale text (as if captured before
        // the sheet visually swapped to draft 2).
        let taskB = Task { @MainActor in
            await sut.acceptDraft(question: "Q1", answer: "A1")
        }

        // Let task B's Task actually run its reentrancy check while task A
        // is still parked in the gate (i.e. `isProcessingAccept == true`).
        await Task.yield()
        await Task.yield()

        gate.fireOldest()
        await taskA.value
        await taskB.value

        // Only draft 1 was ever persisted, with its own correct content —
        // task B's overlapping call was ignored, not applied to draft 2.
        #expect(mockStore.cards.count == 1)
        #expect(mockStore.cards.first?.question == "Q1")
        #expect(mockStore.cards.first?.answer == "A1")

        // Draft 2 is untouched and still presented, ready for its own,
        // uncorrupted accept.
        let stillPresented = try #require(sut.presentedDraft)
        #expect(stillPresented.draft.question == "Q2")
        #expect(stillPresented.draft.answer == "A2")
    }

    @Test("after an overlapping call is ignored, accepting the still-presented second draft succeeds normally")
    func secondDraftCanStillBeAcceptedNormallyAfterAnIgnoredOverlap() async throws {
        let d1 = CardDraft(question: "Q1", answer: "A1")
        let d2 = CardDraft(question: "Q2", answer: "A2")
        let mockStore = MockCardStore()
        let gate = AwaitGate()
        let sut = AppState(cardAuthor: MockCardAuthoringService(drafts: [d1, d2]), cardStore: mockStore)

        // A single capture whose stream yields both drafts (#29: enqueue now
        // fully drains generateDrafts(from:), so one call queues both).
        await sut.enqueue(resolvedText: "text1")

        mockStore.createGate = { await gate.wait() }
        let taskA = Task { @MainActor in
            await sut.acceptDraft(question: "Q1", answer: "A1")
        }
        await waitUntil { gate.callCount >= 1 }

        let taskB = Task { @MainActor in
            await sut.acceptDraft(question: "Q1", answer: "A1")
        }
        await Task.yield()
        await Task.yield()

        gate.fireOldest()
        await taskA.value
        await taskB.value
        mockStore.createGate = nil

        // A fresh, correct accept of draft 2 afterwards is unaffected by
        // the earlier ignored overlap.
        await sut.acceptDraft(question: "Q2", answer: "A2")

        #expect(mockStore.cards.count == 2)
        #expect(mockStore.cards.map(\.question) == ["Q1", "Q2"])
        #expect(sut.presentedDraft == nil)
    }
}
