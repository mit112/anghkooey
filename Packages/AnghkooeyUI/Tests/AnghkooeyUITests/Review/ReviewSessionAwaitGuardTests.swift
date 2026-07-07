import Testing
import Foundation
@testable import AnghkooeyUI
import AnghkooeyCore
import AnghkooeyIntelligence

/// Regression coverage for the epic8 adversarial-review findings: three
/// `ReviewSession` async methods captured a card/draft, `await`ed a
/// store/service call, then wrote published session state on resume
/// *without* re-checking that the thing they operated on was still current.
/// A concurrent `loadDueQueue()` (fired from `.task` / scenePhase / the
/// `.anghkooeyCardAccepted` notification, or the #23 deferred retry) can
/// change `currentCard` during the await, so the resume would clobber the
/// wrong card. These tests pin the post-await re-check guards that fix that.
///
/// Every test drives the same interleaving shape: seed two cards where the
/// *second* only becomes due once the injected clock advances, start the
/// method under test as a child `Task` so it can suspend mid-await on a
/// controllable gate, let a concurrent `loadDueQueue()` run while it's
/// parked there (flipping `currentCard` to the second card), then resume the
/// gate and assert the original write landed but the live session state
/// was left alone.
@Suite("ReviewSession — epic8 post-await re-check guards")
@MainActor
struct ReviewSessionAwaitGuardTests {

    // MARK: - Test doubles

    /// Mutable time source injected as `clock`. A plain `{ now }` closure
    /// over a `let` can't move "now" forward between two `loadDueQueue()`
    /// calls on the same session — needed here to make the second card
    /// become due only once the test decides to reveal it. Mirrors `ClockBox`
    /// in `ReviewSessionErrorHandlingTests`.
    private final class ClockBox: @unchecked Sendable {
        var date: Date
        init(_ date: Date) { self.date = date }
    }

    /// Generic controllable suspension point for a mocked async call.
    /// Mirrors the `SleepGate` pattern used in `ReviewSessionRequeueTests` /
    /// `ErrorPresenterTests`, generalized beyond `sleep(_:)`: any awaited
    /// call can be wired to suspend here until the test resumes it, which is
    /// what lets a test land a second, concurrent `loadDueQueue()` squarely
    /// inside the first call's in-flight await.
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

        /// Resumes the oldest still-pending `wait()` call, as if the mocked
        /// work it stands in for had just finished.
        func fireOldest() {
            guard !pending.isEmpty else { return }
            pending.removeFirst().resume()
        }
    }

    /// Deterministic `MnemonicService` stub whose `generateMnemonic` call
    /// suspends on an `AwaitGate` before returning — the mnemonic-generation
    /// counterpart to `MockCardStore.applyGate`/`updateGate`. Defined locally
    /// (rather than added to the shared `MockMnemonicService`) since only
    /// this suite needs a gateable generation call.
    private final class GatingMnemonicService: MnemonicService, @unchecked Sendable {
        private let text: String
        private let gate: AwaitGate

        init(text: String, gate: AwaitGate) {
            self.text = text
            self.gate = gate
        }

        var availability: AuthoringAvailability {
            get async { .available }
        }

        func generateMnemonic(question: String, answer: String) async throws -> String {
            await gate.wait()
            return text
        }
    }

    /// Waits for `condition` to become true by cooperatively yielding the
    /// MainActor, so a just-resumed continuation gets scheduled and runs to
    /// completion. Bounded so a genuine regression fails fast instead of
    /// hanging. No timers, no real-time wait — mirrors `ReviewSessionRequeueTests`.
    private func waitUntil(
        maxIterations: Int = 10_000,
        _ condition: () -> Bool
    ) async {
        for _ in 0..<maxIterations {
            if condition() { return }
            await Task.yield()
        }
    }

    // MARK: - Bug 1: applyGrade advances/records against the LIVE queue, not the graded card

    @Test("applyGrade: X's grade lands in the store, but a currentCard that changed to Y during the await is not advanced or recorded into")
    func applyGradeDoesNotAdvanceOrRecordWhenCurrentCardChangedDuringAwait() async throws {
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        let clockBox = ClockBox(t0)
        let store = MockCardStore()
        let gate = AwaitGate()

        // cardY is inserted FIRST but isn't due until t0+10 — MockCardStore's
        // dueCards(asOf:) preserves insertion order (no sort), so once Y
        // becomes due it sorts ahead of X in the filtered array below.
        let cardY = try await store.create(question: "QY", answer: "AY", sourceSpan: nil, now: t0.addingTimeInterval(10))
        let cardX = try await store.create(question: "QX", answer: "AX", sourceSpan: nil, now: t0)

        let session = ReviewSession(
            store: store,
            scheduler: { MockFSRS6Engine() },
            clock: { clockBox.date }
        )
        await session.loadDueQueue()
        #expect(session.currentCard?.id == cardX.id) // only X is due at t0

        session.revealAnswer()
        store.applyGate = { await gate.wait() }

        let submitTask = Task { @MainActor in
            await session.submit(grade: .good)
        }

        await waitUntil { gate.callCount >= 1 }

        // A concurrent reload (scenePhase / .anghkooeyCardAccepted / the #18
        // wake) lands while X's grade write is still in flight — Y is now
        // also due, and becomes currentCard; X is pushed into the queue.
        clockBox.date = t0.addingTimeInterval(10)
        await session.loadDueQueue()
        #expect(session.currentCard?.id == cardY.id)
        #expect(session.queueRemaining == 1) // X: still queued, not dropped

        gate.fireOldest()
        await submitTask.value

        // X's grade landed — the store write is correct and must not be lost.
        #expect(store.reviewLogs.map(\.cardID) == [cardX.id])
        // But the now-superseded applyGrade call must not touch the reload's
        // state: Y is still current, X is still queued, and the fresh
        // summary the reload seeded is untouched.
        #expect(session.currentCard?.id == cardY.id)
        #expect(session.queueRemaining == 1)
        #expect(session.summary.reviewed == 0)
    }

    // MARK: - Bug 2: submitEdit writes the snapshot back without re-checking after the await

    @Test("submitEdit: X's edit lands in the store, but a currentCard that changed to Y during the await is not overwritten with X's edited text")
    func submitEditDoesNotOverwriteCurrentCardWhenItChangedDuringAwait() async throws {
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        let clockBox = ClockBox(t0)
        let store = MockCardStore()
        let gate = AwaitGate()

        let cardY = try await store.create(question: "QY", answer: "AY", sourceSpan: nil, now: t0.addingTimeInterval(10))
        let cardX = try await store.create(question: "QX", answer: "AX", sourceSpan: nil, now: t0)

        let session = ReviewSession(
            store: store,
            scheduler: { MockFSRS6Engine() },
            clock: { clockBox.date }
        )
        await session.loadDueQueue()
        #expect(session.currentCard?.id == cardX.id)

        store.updateGate = { await gate.wait() }

        let editTask = Task { @MainActor in
            try await session.submitEdit(cardID: cardX.id, question: "Edited Q", answer: "Edited A", tags: [])
        }

        await waitUntil { gate.callCount >= 1 }

        // A concurrent reload lands while X's update write is still in
        // flight — Y becomes due and takes over as currentCard.
        clockBox.date = t0.addingTimeInterval(10)
        await session.loadDueQueue()
        #expect(session.currentCard?.id == cardY.id)

        gate.fireOldest()
        try await editTask.value

        // X's edit persisted — the store write is correct and must not be lost.
        let storedX = try await store.allCards().first { $0.id == cardX.id }
        #expect(storedX?.question == "Edited Q")
        #expect(storedX?.answer == "Edited A")

        // But Y's live snapshot must not be clobbered with X's edited text.
        #expect(session.currentCard?.id == cardY.id)
        #expect(session.currentCard?.question == "QY")
        #expect(session.currentCard?.answer == "AY")
    }

    // MARK: - Bug 3: generateMnemonic publishes stale text onto a later card

    @Test("generateMnemonic: X's stale mnemonic is discarded, not published or persisted, when currentCard changed to Y during generation")
    func generateMnemonicDoesNotPublishStaleTextWhenCurrentCardChangedDuringAwait() async throws {
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        let clockBox = ClockBox(t0)
        let store = MockCardStore()
        let gate = AwaitGate()
        let service = GatingMnemonicService(text: "X's stale mnemonic.", gate: gate)

        let cardY = try await store.create(question: "QY", answer: "AY", sourceSpan: nil, now: t0.addingTimeInterval(10))
        let cardX = try await store.create(question: "QX", answer: "AX", sourceSpan: nil, now: t0)

        let session = ReviewSession(
            store: store,
            scheduler: { MockFSRS6Engine() },
            clock: { clockBox.date },
            mnemonicService: service
        )
        await session.loadDueQueue()
        #expect(session.currentCard?.id == cardX.id)

        let genTask = Task { @MainActor in
            await session.generateMnemonic()
        }

        await waitUntil { gate.callCount >= 1 }
        #expect(session.isMnemonicLoading == true)

        // A concurrent reload lands while generation for X is still in
        // flight — Y becomes due and takes over as currentCard.
        clockBox.date = t0.addingTimeInterval(10)
        await session.loadDueQueue()
        #expect(session.currentCard?.id == cardY.id)

        gate.fireOldest()
        await genTask.value

        // X's generated text must not appear on screen (Y has no stored
        // mnemonic, so a correct outcome leaves currentMnemonic nil) and
        // must not be persisted against X either — it's discarded, not saved.
        #expect(session.currentMnemonic == nil)
        #expect(session.isMnemonicLoading == false)
        let storedX = try await store.allCards().first { $0.id == cardX.id }
        #expect(storedX?.mnemonic == nil)
    }
}
