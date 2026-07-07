import Testing
import Foundation
@testable import Anghkooey
import AnghkooeyCore

// MARK: - #28 drain() reentrancy guard coverage
//
// `AppState.drain()` is invoked from three unsynchronized triggers (launch
// `.task`, scenePhase `.active`, and the Darwin-notification observer), and
// it suspends at several points (`drainer.drain()`,
// `widgetReconciler.reconcile()`, `refreshScheduler()`). Without a
// reentrancy guard, a second concurrent call runs its own
// `beginDrainPass()` — resetting `failedDrainItemCount` to zero — while the
// first pass is still recording drops via `recordDrainFailure`, corrupting
// or silently swallowing the end-of-pass "Couldn't read N items" summary
// (reopening #28's own bug). Mirrors the `isProcessingAccept` guard already
// covered by `AppStateAcceptDraftReentrancyTests`.
//
// `InboxDrainer` isn't injectable — `AppState` constructs a concrete
// instance internally — so this suite can't gate the exact suspension point
// described in the bug report. Instead it drives the real `drain()` method
// end-to-end and uses `MockCardStore.optimizationReviewLogsGate`, which
// gates the suspension point inside `refreshScheduler()` (the last `await`
// in `drain()`, reached after `drainer.drain()` has already returned), to
// hold the first pass open long enough to prove a second, overlapping
// `drain()` call is dropped rather than resetting shared state.

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

@Suite("AppState.drain — #28 reentrancy guard")
@MainActor
struct AppStateDrainReentrancyTests {

    private struct StubError: Error {}

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

    @Test("a second drain() call that overlaps the first's in-flight pass is a no-op: the first pass's drop count survives untouched")
    func overlappingDrainDoesNotResetTheFailureCounter() async throws {
        let mockStore = MockCardStore()
        let gate = AwaitGate()
        let sut = AppState(cardStore: mockStore)

        mockStore.optimizationReviewLogsGate = { await gate.wait() }

        // Pass 1: drain() runs beginDrainPass() + drainer.drain() + the
        // widget reconcile, then suspends inside refreshScheduler().
        let taskA = Task { @MainActor in
            await sut.drain()
        }
        await waitUntil { gate.callCount >= 1 }

        // Simulate two items dropped during pass 1 (as `DrainerBridge`
        // would report via `recordDrainFailure` while `drainer.drain()` is
        // running — which, for this call, has already completed by the
        // time it reaches the gate below).
        sut.recordDrainFailure(StubError())
        sut.recordDrainFailure(StubError())

        // Pass 2: an overlapping trigger (e.g. a foreground transition
        // while the Darwin-notification-triggered pass is still running).
        let taskB = Task { @MainActor in
            await sut.drain()
        }

        // Let task B's Task actually run its reentrancy check while task A
        // is still parked in the gate (i.e. `isDraining == true`).
        await Task.yield()
        await Task.yield()

        // With the guard in place, task B returns immediately without ever
        // calling beginDrainPass() or reaching the gate a second time — if
        // it had, this await would hang, since only one continuation is
        // ever resumed below.
        await taskB.value
        #expect(gate.callCount == 1)

        gate.fireOldest()
        await taskA.value

        // Task B's overlapping call never reset the counter: the summary
        // still reports both drops recorded during pass 1.
        #expect(sut.rootErrorPresenter.toast?.message == "Couldn't read 2 captured item(s). Try sharing them again.")
    }
}
