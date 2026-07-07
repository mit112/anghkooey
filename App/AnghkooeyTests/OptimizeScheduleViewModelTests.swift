import Testing
import Foundation
@testable import Anghkooey
@testable import AnghkooeyCore
import AnghkooeyUI

@MainActor
@Suite("OptimizeScheduleViewModel")
struct OptimizeScheduleViewModelTests {

    private struct StubError: Error {}

    /// Captures each `optimizationReviewLogsGate` call as a suspended
    /// continuation so a test can resume it on demand instead of racing a
    /// real suspension. Mirrors the `AwaitGate` pattern used in
    /// `AppStateAcceptDraftReentrancyTests` — needed because `MockCardStore`
    /// is a plain class, not an actor, so without an explicit gate two
    /// `optimize()` calls never genuinely overlap.
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

    /// Waits for `condition` to become true by cooperatively yielding the
    /// MainActor. Bounded so a genuine regression fails fast instead of
    /// hanging. Mirrors `AppStateAcceptDraftReentrancyTests`.
    private func waitUntil(
        maxIterations: Int = 10_000,
        _ condition: () -> Bool
    ) async {
        for _ in 0..<maxIterations {
            if condition() { return }
            await Task.yield()
        }
    }

    /// A trivial second actor whose sole purpose is to force a *genuine*
    /// cross-actor hop off the MainActor and back. Reproduces the exact
    /// ingredient in the #27 fix-1 bug report: the queued
    /// `Task { @MainActor ... }` progress ticks only get a chance to run
    /// once the caller actually suspends off MainActor (as
    /// `AppState.refreshScheduler()`'s real `cardStore.optimizationReviewLogs()`
    /// await does via the actor-isolated `CardStore` in production) — a bare
    /// `Task.yield()` loop or a `Task.sleep` does not reliably flush them in
    /// this environment (confirmed empirically while writing this test).
    private actor Hop {
        func hop() async {}
    }

    /// Builds `count` distinct-card review-log pairs, each contributing
    /// exactly one eligible sample (a first same-day review followed by a
    /// later non-same-day review), so the returned row set yields
    /// `eligibleSampleCount == count` regardless of the per-card
    /// `maxSequenceLength` cap.
    private func eligibleRows(_ count: Int) -> [OptimizationReviewLogRow] {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        var rows: [OptimizationReviewLogRow] = []
        for _ in 0..<count {
            let card = UUID()
            rows.append(OptimizationReviewLogRow(cardID: card, reviewedAt: base, rating: .good, elapsedDays: 0))
            rows.append(OptimizationReviewLogRow(
                cardID: card, reviewedAt: base.addingTimeInterval(86_400), rating: .good, elapsedDays: 1))
        }
        return rows
    }

    @Test("under threshold shows locked state with eligible count")
    func lockedState() async {
        let store = MockCardStore()
        store.optimizationReviewLogsOverride = eligibleRows(5)
        let vm = OptimizeScheduleViewModel(
            store: store,
            optimizer: MockFSRSOptimizer(),
            paramsStore: MockOptimizedParametersStore())
        await vm.refresh()
        #expect(vm.phase == .locked(eligible: 5))
        #expect(vm.unlockThreshold == 512)
    }

    @Test("at/above threshold shows ready state with eligible count")
    func readyState() async {
        let store = MockCardStore()
        store.optimizationReviewLogsOverride = eligibleRows(512)
        let vm = OptimizeScheduleViewModel(
            store: store,
            optimizer: MockFSRSOptimizer(),
            paramsStore: MockOptimizedParametersStore())
        await vm.refresh()
        #expect(vm.phase == .ready(eligible: 512))
    }

    @Test("a store failure in refresh() surfaces as .failed, never .locked")
    func refreshStoreFailureIsNotLocked() async {
        let store = MockCardStore()
        // A heavy user (many eligible reviews) hits a transient store error.
        store.optimizationReviewLogsOverride = eligibleRows(900)
        store.optimizationReviewLogsError = StubError()
        let vm = OptimizeScheduleViewModel(
            store: store,
            optimizer: MockFSRSOptimizer(),
            paramsStore: MockOptimizedParametersStore())
        await vm.refresh()
        guard case .failed = vm.phase else {
            Issue.record("Expected .failed, got \(vm.phase) — a store error must never be reported as .locked")
            return
        }
    }

    @Test("a store failure in optimize() surfaces as .failed")
    func optimizeStoreFailure() async {
        let store = MockCardStore()
        store.optimizationReviewLogsError = StubError()
        let vm = OptimizeScheduleViewModel(
            store: store,
            optimizer: MockFSRSOptimizer(),
            paramsStore: MockOptimizedParametersStore())
        await vm.optimize()
        guard case .failed = vm.phase else {
            Issue.record("Expected .failed, got \(vm.phase)")
            return
        }
    }

    @Test("a params-save failure surfaces as .failed, not .complete, and nothing is persisted")
    func saveFailureIsNotComplete() async {
        let store = MockCardStore()
        store.optimizationReviewLogsOverride = eligibleRows(512)
        let paramsStore = MockOptimizedParametersStore()
        paramsStore.saveError = StubError()
        let vm = OptimizeScheduleViewModel(
            store: store,
            optimizer: MockFSRSOptimizer(),
            paramsStore: paramsStore)
        await vm.optimize()
        guard case let .failed(message) = vm.phase else {
            Issue.record("Expected .failed, got \(vm.phase) — a save failure must never show as .complete")
            return
        }
        #expect(message.contains("saved"))
        #expect(paramsStore.savedParameters.isEmpty)
    }

    @Test("successful optimize with successful save reaches .complete and persists the params")
    func runProducesResultAndPersists() async {
        let store = MockCardStore()
        store.optimizationReviewLogsOverride = eligibleRows(512)
        let paramsStore = MockOptimizedParametersStore()
        let vm = OptimizeScheduleViewModel(
            store: store,
            optimizer: MockFSRSOptimizer(),
            paramsStore: paramsStore)
        await vm.optimize()
        guard case let .complete(result) = vm.phase else {
            Issue.record("Expected .complete, got \(vm.phase)")
            return
        }
        #expect(result.optimizedLoss == 0.42)
        #expect(paramsStore.savedParameters.count == 1)
    }

    @Test("retry after a refresh() failure re-runs refresh()")
    func retryAfterRefreshFailureRecovers() async {
        let store = MockCardStore()
        store.optimizationReviewLogsError = StubError()
        let vm = OptimizeScheduleViewModel(
            store: store,
            optimizer: MockFSRSOptimizer(),
            paramsStore: MockOptimizedParametersStore())
        await vm.refresh()
        guard case .failed = vm.phase else {
            Issue.record("Expected .failed, got \(vm.phase)")
            return
        }
        store.optimizationReviewLogsError = nil
        store.optimizationReviewLogsOverride = eligibleRows(5)
        await vm.retry()
        #expect(vm.phase == .locked(eligible: 5))
    }

    // MARK: - #27 review fixes

    @Test("optimize() reaches .complete and stays there once every progress tick has been delivered")
    func staleProgressTickDoesNotClobberCompletePhase() async {
        let store = MockCardStore()
        store.optimizationReviewLogsOverride = eligibleRows(512)
        let paramsStore = MockOptimizedParametersStore()
        let vm = OptimizeScheduleViewModel(
            store: store,
            optimizer: MockFSRSOptimizer(),
            paramsStore: paramsStore)

        await vm.optimize()
        guard case .complete = vm.phase else {
            Issue.record("Expected .complete immediately after optimize(), got \(vm.phase)")
            return
        }

        // Drain the MainActor executor so every progress Task the optimizer
        // enqueued gets a chance to run (each checks `currentRunID` against
        // its own captured run token before touching `phase` — see
        // `optimize()`). Confirms a completed run's phase isn't disturbed by
        // its own trailing progress callbacks (#27 fix 1). Note: in this
        // harness the MainActor executor was observed (via instrumentation
        // added while writing this test) to always finish delivering
        // already-enqueued jobs before `optimize()`'s own continuation
        // resumes, so this test cannot force the pre-fix ordering the
        // reviewer observed in the running app; it still pins the
        // post-condition and exercises the exact guarded code path.
        let hopper = Hop()
        await Task.yield()
        await hopper.hop()

        guard case let .complete(result) = vm.phase else {
            Issue.record("Expected phase to remain .complete after progress ticks flush, got \(vm.phase)")
            return
        }
        #expect(result.optimizedLoss == 0.42)
    }

    @Test("a second concurrent optimize() call while one is in flight is a no-op")
    func concurrentOptimizeCallIsGated() async throws {
        let store = MockCardStore()
        store.optimizationReviewLogsOverride = eligibleRows(512)
        let gate = AwaitGate()
        store.optimizationReviewLogsGate = { await gate.wait() }
        let paramsStore = MockOptimizedParametersStore()
        let vm = OptimizeScheduleViewModel(
            store: store,
            optimizer: MockFSRSOptimizer(),
            paramsStore: paramsStore)

        // Tap 1: starts optimize() and parks it mid-flight inside the gated
        // store read, before `phase` has left `.ready`.
        let taskA = Task { @MainActor in await vm.optimize() }
        await waitUntil { gate.callCount >= 1 }

        // Tap 2: a rapid double-tap firing while task A is still in flight.
        let taskB = Task { @MainActor in await vm.optimize() }
        await Task.yield()
        await Task.yield()

        // Task B must have been rejected by the reentrancy guard without
        // ever touching the gated store call.
        #expect(gate.callCount == 1)

        gate.fireOldest()
        await taskA.value
        await taskB.value

        // Exactly one run executed and persisted.
        #expect(paramsStore.savedParameters.count == 1)
        guard case .complete = vm.phase else {
            Issue.record("Expected .complete, got \(vm.phase)")
            return
        }
    }

    @Test("retry after an optimize() store failure re-runs optimize() and recovers")
    func retryAfterOptimizeStoreFailureRecovers() async {
        let store = MockCardStore()
        store.optimizationReviewLogsError = StubError()
        let paramsStore = MockOptimizedParametersStore()
        let vm = OptimizeScheduleViewModel(
            store: store,
            optimizer: MockFSRSOptimizer(),
            paramsStore: paramsStore)

        await vm.optimize()
        guard case .failed = vm.phase else {
            Issue.record("Expected .failed, got \(vm.phase)")
            return
        }

        store.optimizationReviewLogsError = nil
        store.optimizationReviewLogsOverride = eligibleRows(512)
        await vm.retry()

        guard case let .complete(result) = vm.phase else {
            Issue.record("Expected .complete after retry, got \(vm.phase)")
            return
        }
        #expect(result.optimizedLoss == 0.42)
        #expect(paramsStore.savedParameters.count == 1)
    }

    @Test("retry after an optimize() save failure re-runs optimize() and recovers")
    func retryAfterOptimizeSaveFailureRecovers() async {
        let store = MockCardStore()
        store.optimizationReviewLogsOverride = eligibleRows(512)
        let paramsStore = MockOptimizedParametersStore()
        paramsStore.saveError = StubError()
        let vm = OptimizeScheduleViewModel(
            store: store,
            optimizer: MockFSRSOptimizer(),
            paramsStore: paramsStore)

        await vm.optimize()
        guard case .failed = vm.phase else {
            Issue.record("Expected .failed, got \(vm.phase)")
            return
        }
        #expect(paramsStore.savedParameters.isEmpty)

        paramsStore.saveError = nil
        await vm.retry()

        guard case let .complete(result) = vm.phase else {
            Issue.record("Expected .complete after retry, got \(vm.phase)")
            return
        }
        #expect(result.optimizedLoss == 0.42)
        #expect(paramsStore.savedParameters.count == 1)
    }
}
