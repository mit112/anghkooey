import Testing
import Foundation
@testable import AnghkooeyUI
import AnghkooeyCore

/// Issue #18 — cards graded "Again" (or any FSRS learning-step reschedule)
/// vanish until the next `loadDueQueue()` (a scenePhase change or the
/// `.anghkooeyCardAccepted` notification), because `submit(grade:)` only
/// advances through the queue seeded at the last `loadDueQueue()` call. A
/// card rescheduled minutes into the future is invisible in-session even
/// though the user is still sitting there.
///
/// These tests pin the fix: when the queue empties, `ReviewSession` re-checks
/// the store instead of unconditionally declaring `.empty`, and — if nothing
/// is due yet but something will be soon — schedules exactly one wake for
/// that instant instead of polling.
@Suite("ReviewSession — Issue #18 requeue contract")
@MainActor
struct ReviewSessionRequeueTests {

    // MARK: - Test doubles

    /// Mutable, test-controlled time source injected as `clock`. Lets a test
    /// move "now" forward between `loadDueQueue()` calls without any real
    /// wall-clock wait.
    ///
    /// Not actor-isolated (unlike `SleepGate` below) because `ReviewSession`'s
    /// `clock` closure type is a plain synchronous `@Sendable () -> Date` —
    /// it can't hop actors to read a `@MainActor`-isolated property. Safe as
    /// `@unchecked Sendable`: every access in this file happens from the
    /// MainActor test body or from `ReviewSession`'s own MainActor-isolated
    /// methods, same reasoning as `MockCardStore`'s own `@unchecked Sendable`.
    private final class TestClock: @unchecked Sendable {
        private(set) var now: Date
        init(_ now: Date) { self.now = now }
        func advance(by seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
    }

    /// Captures each `sleep(_:)` call as a suspended continuation so a test
    /// can fire the "timer" on demand instead of waiting on a real duration.
    /// Mirrors `ErrorPresenterTests.SleepGate` (#22) exactly — same reasoning
    /// applies: kept `@MainActor`-isolated so firing the gate and yielding is
    /// deterministic rather than racing a background executor hop.
    @MainActor
    private final class SleepGate: @unchecked Sendable {
        private var pending: [CheckedContinuation<Void, Never>] = []
        private(set) var callCount = 0
        private(set) var durations: [Duration] = []

        func sleep(_ duration: Duration) async {
            await withCheckedContinuation { continuation in
                callCount += 1
                durations.append(duration)
                pending.append(continuation)
            }
        }

        /// Resumes the oldest still-pending `sleep` call, as if its timer fired.
        func fireOldest() {
            guard !pending.isEmpty else { return }
            pending.removeFirst().resume()
        }
    }

    /// Waits for `condition` to become true by cooperatively yielding the
    /// MainActor, so a just-resumed continuation gets scheduled and runs to
    /// completion. Bounded so a genuine regression fails fast instead of
    /// hanging. No timers, no real-time wait — mirrors `ErrorPresenterTests`.
    private func waitUntil(
        maxIterations: Int = 10_000,
        _ condition: () -> Bool
    ) async {
        for _ in 0..<maxIterations {
            if condition() { return }
            await Task.yield()
        }
    }

    private func makeSession(
        store: MockCardStore,
        clock: TestClock,
        sleepGate: SleepGate,
        dailyBatchCap: Int = 20,
        backlogThreshold: Int = 50
    ) -> ReviewSession {
        ReviewSession(
            store: store,
            scheduler: { MockFSRS6Engine() },
            clock: { clock.now },
            sleep: { duration in await sleepGate.sleep(duration) },
            dailyBatchCap: dailyBatchCap,
            backlogThreshold: backlogThreshold
        )
    }

    // MARK: - Re-seed test (the key one)

    @Test("queue emptying with an upcoming learning-step card sets nextDueDate and schedules exactly one wake; firing it re-seeds the card")
    func requeuesAgainCardWhenLearningStepBecomesDue() async throws {
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        let clock = TestClock(t0)
        let sleepGate = SleepGate()
        let store = MockCardStore()

        // Card due right now — the only thing loaded into the visible queue.
        let dueNow = try await store.create(question: "Q1", answer: "A1", sourceSpan: nil, now: t0)
        // Simulates an "Again" card whose FSRS learning step lands 180s out —
        // not due yet at load time, so it's invisible to `loadDueQueue()`.
        let againCard = try await store.create(question: "Q2 (again)", answer: "A2", sourceSpan: nil, now: t0.addingTimeInterval(180))

        let session = makeSession(store: store, clock: clock, sleepGate: sleepGate)
        await session.loadDueQueue()
        #expect(session.currentCard?.id == dueNow.id)

        session.revealAnswer()
        await session.submit(grade: .good) // grades the only due card; queue empties

        // Must NOT be stuck on a bare "All caught up" — a card is coming due
        // in 180s and the session must know it, not just sit inert.
        #expect(session.state == .empty)
        #expect(session.nextDueDate == t0.addingTimeInterval(180))
        await waitUntil { sleepGate.callCount >= 1 }
        #expect(sleepGate.callCount == 1)
        #expect(sleepGate.durations.last == .seconds(180))

        // Advance the injected clock to the learning-step due time, then fire
        // the scheduled wake as if its timer elapsed.
        clock.advance(by: 180)
        sleepGate.fireOldest()

        await waitUntil { session.state == .reviewing }
        #expect(session.state == .reviewing)
        #expect(session.currentCard?.id == againCard.id)
    }

    // MARK: - Cushion Mode is respected on queue-empty (no immediate re-seed)

    @Test("queue emptying with cushion-held backlog still due now does not dump the backlog into the queue — Cushion Mode stays capped")
    func cushionHeldBacklogIsNotDumpedWhenQueueEmpties() async throws {
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        let clock = TestClock(t0)
        let sleepGate = SleepGate()
        let store = MockCardStore()

        // Two cards due right now; Cushion Mode caps the visible batch to 1
        // so the second is due but held back — it must STAY held when the
        // visible batch empties, not get dumped into the queue. Re-seeding
        // held-back backlog (even re-capped) would defeat Cushion Mode's
        // "one capped batch per load" contract.
        let cardA = try await store.create(question: "Q1", answer: "A1", sourceSpan: nil, now: t0)
        let cardB = try await store.create(question: "Q2", answer: "A2", sourceSpan: nil, now: t0)

        let session = makeSession(store: store, clock: clock, sleepGate: sleepGate, dailyBatchCap: 1, backlogThreshold: 0)
        await session.loadDueQueue()
        #expect(session.isCushionActive)
        #expect(session.currentCard?.id == cardA.id)
        #expect(session.queueRemaining == 0) // capped batch: only the current card is visible

        session.revealAnswer()
        await session.submit(grade: .good) // grades cardA, the visible batch's only card; queue empties, but cardB is still due and held back

        // cardB must NOT have been dumped into the session — it's still
        // sitting untouched and due in the store, exactly as before. (Any
        // `nextDueDate` shown here would reflect cardA's own new schedule
        // from being graded, not cardB — cardB is due *at* now, not
        // *after* now, so it never contributes an ETA; that's orthogonal to
        // what this test is pinning, which is that it was never surfaced or
        // consumed.)
        #expect(session.state == .empty)
        #expect(session.currentCard == nil)
        #expect(session.queueRemaining == 0)
        let stillDue = try await store.dueCards(asOf: t0)
        #expect(stillDue.map(\.id) == [cardB.id]) // cardB: untouched, never surfaced, never consumed
    }

    // MARK: - Finding 3 regression: ETA/wake survive a reload while pending

    @Test("Finding 3: a foreground reload after the queue empties with an ETA pending re-establishes nextDueDate and re-schedules the wake")
    func reloadAfterEmptyReestablishesETAAndWake() async throws {
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        let clock = TestClock(t0)
        let sleepGate = SleepGate()
        let store = MockCardStore()

        _ = try await store.create(question: "Q1", answer: "A1", sourceSpan: nil, now: t0)
        let againCard = try await store.create(question: "Q2 (again)", answer: "A2", sourceSpan: nil, now: t0.addingTimeInterval(180))

        let session = makeSession(store: store, clock: clock, sleepGate: sleepGate)
        await session.loadDueQueue()
        session.revealAnswer()
        await session.submit(grade: .good) // queue empties; wake scheduled for t0+180

        await waitUntil { sleepGate.callCount >= 1 }
        #expect(sleepGate.callCount == 1)
        #expect(session.nextDueDate == t0.addingTimeInterval(180))

        // Simulate the app backgrounding and foregrounding again — a
        // scenePhase-triggered `loadDueQueue()` firing before the wake
        // fires. Before the fix, `loadDueQueue()` unconditionally nil'd
        // `nextDueDate` and cancelled the wake without ever recomputing
        // them, permanently dropping the ETA even though `againCard` is
        // still upcoming.
        await session.loadDueQueue()

        #expect(session.state == .empty)
        #expect(session.nextDueDate == t0.addingTimeInterval(180))
        await waitUntil { sleepGate.callCount >= 2 }
        #expect(sleepGate.callCount == 2)

        // Confirm the re-established wake isn't just cosmetic: firing the
        // stale (first, now-cancelled) wake must not re-seed, but firing the
        // live (second) one must.
        clock.advance(by: 180)
        sleepGate.fireOldest()
        await waitUntil(maxIterations: 500) { session.state == .reviewing }
        #expect(session.state == .empty)

        sleepGate.fireOldest()
        await waitUntil { session.state == .reviewing }
        #expect(session.state == .reviewing)
        #expect(session.currentCard?.id == againCard.id)
    }

    // MARK: - Finding 4: summary survives the wake re-seed, but not a fresh reload

    @Test("Finding 4: the scheduled wake preserves summary.reviewed across the re-seed, but an external loadDueQueue() resets it")
    func wakePreservesSummaryButExternalReloadResetsIt() async throws {
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        let clock = TestClock(t0)
        let sleepGate = SleepGate()
        let store = MockCardStore()

        _ = try await store.create(question: "Q1", answer: "A1", sourceSpan: nil, now: t0)
        _ = try await store.create(question: "Q2", answer: "A2", sourceSpan: nil, now: t0)
        let againCard = try await store.create(question: "Q3 (again)", answer: "A3", sourceSpan: nil, now: t0.addingTimeInterval(180))

        let session = makeSession(store: store, clock: clock, sleepGate: sleepGate)
        await session.loadDueQueue()

        // Grade both due cards ("good") — the third (learning-step) card
        // isn't due yet, so the queue empties after the second grade and a
        // wake gets scheduled for it.
        session.revealAnswer()
        await session.submit(grade: .good)
        session.revealAnswer()
        await session.submit(grade: .good)

        #expect(session.state == .empty)
        #expect(session.summary.reviewed == 2)
        await waitUntil { sleepGate.callCount >= 1 }
        #expect(session.nextDueDate == t0.addingTimeInterval(180))

        // Fire the wake — it re-seeds via `loadDueQueue(resetSummary: false)`,
        // preserving the running tally from this same sitting.
        clock.advance(by: 180)
        sleepGate.fireOldest()
        await waitUntil { session.state == .reviewing }

        #expect(session.state == .reviewing)
        #expect(session.currentCard?.id == againCard.id)
        #expect(session.summary.reviewed == 2) // preserved — not reset by the wake

        // An ordinary external reload (scenePhase/notification) DOES reset
        // it — that's a fresh sitting, not a continuation of this one.
        await session.loadDueQueue()
        #expect(session.summary.reviewed == 0)
    }

    // MARK: - No-upcoming test

    @Test("queue emptying with genuinely no upcoming card leaves nextDueDate nil and schedules no wake")
    func noWakeScheduledWhenNothingIsUpcoming() async throws {
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        let clock = TestClock(t0)
        let sleepGate = SleepGate()
        let store = MockCardStore()
        // FSRS always reschedules a graded card into the future, so the only
        // deterministic way to model "nothing at all is upcoming" is via the
        // store's own answer to `nextDueDate(after:)`.
        store.nextDueDateOverride = .some(nil)

        _ = try await store.create(question: "Q1", answer: "A1", sourceSpan: nil, now: t0)

        let session = makeSession(store: store, clock: clock, sleepGate: sleepGate)
        await session.loadDueQueue()

        session.revealAnswer()
        await session.submit(grade: .good)

        #expect(session.state == .empty)
        #expect(session.nextDueDate == nil)
        #expect(session.currentCard == nil)
        await waitUntil(maxIterations: 300) { sleepGate.callCount > 0 }
        #expect(sleepGate.callCount == 0)
    }

    // MARK: - Cancellation test

    @Test("a scheduled wake is cancelled by a subsequent loadDueQueue() and does not fire a stale re-seed")
    func staleWakeIsCancelledByLoadDueQueue() async throws {
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        let clock = TestClock(t0)
        let sleepGate = SleepGate()
        let store = MockCardStore()

        _ = try await store.create(question: "Q1", answer: "A1", sourceSpan: nil, now: t0)
        let cardB = try await store.create(question: "Q2 (again)", answer: "A2", sourceSpan: nil, now: t0.addingTimeInterval(180))

        let session = makeSession(store: store, clock: clock, sleepGate: sleepGate)
        await session.loadDueQueue()
        session.revealAnswer()
        await session.submit(grade: .good) // queue empties; wake scheduled for t0+180

        await waitUntil { sleepGate.callCount >= 1 }
        #expect(sleepGate.callCount == 1)
        #expect(session.nextDueDate == t0.addingTimeInterval(180))

        // Simulate a scenePhase-triggered reload arriving before the wake
        // fires. `loadDueQueue()` must cancel the stale wake — but per the
        // fix (Finding 1/3), the reload re-establishes nextDueDate/wake
        // itself, since cardB is still upcoming: it schedules a *new* wake
        // in place of the one it just cancelled.
        await session.loadDueQueue()
        #expect(session.state == .empty)
        #expect(session.nextDueDate == t0.addingTimeInterval(180))
        #expect(session.currentCard == nil)
        await waitUntil { sleepGate.callCount >= 2 }
        #expect(sleepGate.callCount == 2)

        // Advance the clock so cardB is now due, then fire the STALE (first,
        // now-cancelled) continuation as if its timer had elapsed anyway. A
        // correctly-cancelled task must see `Task.isCancelled == true` and
        // return without re-seeding — state must NOT flip to `.reviewing`.
        clock.advance(by: 180)
        sleepGate.fireOldest()
        await waitUntil(maxIterations: 500) { session.state == .reviewing }

        #expect(session.state == .empty)
        #expect(session.currentCard == nil)
        _ = cardB // referenced only for clarity of intent above
    }
}
