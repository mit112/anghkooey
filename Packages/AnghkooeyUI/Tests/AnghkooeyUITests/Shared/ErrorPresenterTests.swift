import Testing
import Foundation
@testable import AnghkooeyUI

@Suite("ErrorPresenter — Issue #22 contract")
@MainActor
struct ErrorPresenterTests {

    // MARK: - Test doubles

    /// Captures each `sleep(_:)` call as a suspended continuation so a test can
    /// fire the "timer" on demand instead of waiting on a real duration. This is
    /// the injected `sleep` seam's test double — no real-time waits anywhere.
    ///
    /// Kept `@MainActor`-isolated (like `ErrorPresenter` itself) so that
    /// suspending and resuming the continuation both happen on the same serial
    /// executor as the presenter's dismiss task — that's what makes firing the
    /// gate and then yielding deterministic instead of racing a background
    /// executor hop.
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

    private final class AnnounceSpy {
        private(set) var messages: [String] = []
        func record(_ message: String) { messages.append(message) }
    }

    @MainActor
    private final class RetrySpy {
        private(set) var ranCount = 0
        func run() async { ranCount += 1 }
    }

    private struct SampleError: LocalizedError {
        var errorDescription: String? { "Sample failure." }
    }

    /// Waits for `condition` to become true by cooperatively yielding the
    /// MainActor, so a just-resumed continuation gets scheduled and runs to
    /// completion. Swift Testing runs many `@MainActor` tests concurrently, so
    /// a fixed small number of yields isn't reliably enough under contention —
    /// this polls instead, bounded by `maxIterations` so a genuine regression
    /// still fails fast rather than hanging. No timers, no real-time wait.
    private func waitUntil(
        maxIterations: Int = 10_000,
        _ condition: () -> Bool
    ) async {
        for _ in 0..<maxIterations {
            if condition() { return }
            await Task.yield()
        }
    }

    // MARK: - present(_:retry:)

    @Test("present(_:) sets toast with the message; hasRetry is false with no retry")
    func presentSetsToastNoRetry() async {
        let gate = SleepGate()
        let presenter = ErrorPresenter(sleep: { duration in await gate.sleep(duration) }, announce: { _ in })

        presenter.present("Couldn't save.")

        #expect(presenter.toast?.message == "Couldn't save.")
        #expect(presenter.toast?.hasRetry == false)
    }

    @Test("present(_:retry:) sets hasRetry true when a retry closure is provided")
    func presentSetsToastWithRetry() async {
        let gate = SleepGate()
        let presenter = ErrorPresenter(sleep: { duration in await gate.sleep(duration) }, announce: { _ in })

        presenter.present("Couldn't save.", retry: {})

        #expect(presenter.toast?.hasRetry == true)
    }

    @Test("present(_ error:) forwards error.localizedDescription as the message")
    func presentErrorForwardsLocalizedDescription() async {
        let gate = SleepGate()
        let presenter = ErrorPresenter(sleep: { duration in await gate.sleep(duration) }, announce: { _ in })

        presenter.present(SampleError())

        #expect(presenter.toast?.message == "Sample failure.")
    }

    // MARK: - announce seam

    @Test("present(_:) calls the announce seam with the message")
    func presentCallsAnnounce() async {
        let gate = SleepGate()
        let spy = AnnounceSpy()
        let presenter = ErrorPresenter(sleep: { duration in await gate.sleep(duration) }, announce: { spy.record($0) })

        presenter.present("Network unavailable.")

        #expect(spy.messages == ["Network unavailable."])
    }

    // MARK: - auto-dismiss

    @Test("auto-dismiss clears the toast once the injected sleep completes")
    func autoDismissClearsToastAfterSleep() async {
        let gate = SleepGate()
        let presenter = ErrorPresenter(sleep: { duration in await gate.sleep(duration) }, announce: { _ in })

        presenter.present("Couldn't save.")
        #expect(presenter.toast != nil)

        // Wait for the presenter's dismiss task to actually reach its `sleep`
        // call (i.e. register with the gate) before firing it — otherwise
        // `fireOldest()` would be a silent no-op on an empty queue.
        await waitUntil { gate.callCount >= 1 }
        gate.fireOldest()
        await waitUntil { presenter.toast == nil }

        #expect(presenter.toast == nil)
    }

    @Test("presenting a second message cancels the first timer; only the latest dismissal fires")
    func secondPresentCancelsFirstTimer() async {
        let gate = SleepGate()
        let presenter = ErrorPresenter(sleep: { duration in await gate.sleep(duration) }, announce: { _ in })

        presenter.present("First error.")
        let firstID = presenter.toast?.id

        // Barrier: the first toast's timer must register with the gate BEFORE
        // the second is presented, so it is deterministically the oldest
        // pending continuation. Without this, the two unstructured dismiss
        // Tasks race to register and `fireOldest()` could resume the *second*
        // (still-live) timer and wrongly dismiss it (flaky failure).
        await waitUntil { gate.callCount >= 1 }

        presenter.present("Second error.")
        let secondID = presenter.toast?.id
        #expect(firstID != secondID)
        #expect(presenter.toast?.message == "Second error.")

        // Now the second timer registers too; the oldest is the first one.
        await waitUntil { gate.callCount >= 2 }

        // Fire the first (now-cancelled) timer. It must NOT dismiss the second
        // toast — if it wrongly did, `toast` would go nil here and the
        // assertion below would catch it. `maxIterations` is a bounded grace
        // window, not a real-time wait: it never blocks longer than it takes
        // to confirm nothing happened.
        gate.fireOldest()
        await waitUntil(maxIterations: 300) { presenter.toast == nil }
        #expect(presenter.toast?.id == secondID)

        // Fire the second (still active) timer: this is the one that dismisses.
        gate.fireOldest()
        await waitUntil { presenter.toast == nil }
        #expect(presenter.toast == nil)
    }

    // MARK: - dismiss()

    @Test("dismiss() clears the toast and cancels the pending auto-dismiss")
    func dismissClearsToastAndCancelsPending() async {
        let gate = SleepGate()
        let presenter = ErrorPresenter(sleep: { duration in await gate.sleep(duration) }, announce: { _ in })

        presenter.present("A")
        // Barrier: A's timer must register before B is presented, so it is the
        // oldest pending continuation and `fireOldest()` below deterministically
        // fires the dismissed/cancelled one (not B's still-live timer).
        await waitUntil { gate.callCount >= 1 }
        presenter.dismiss()
        #expect(presenter.toast == nil)

        // Present a new toast so a wrongly-still-live first timer has
        // something to clobber. If dismiss() had failed to cancel the first
        // timer, firing it below would dismiss "B" and this test would go
        // green even though nothing was actually cancelled — that's the
        // tautology this replaces.
        presenter.present("B")
        #expect(presenter.toast?.message == "B")

        // Fire the first (dismissed, and should-be-cancelled) timer — both
        // timers are now registered, so the oldest is A's.
        await waitUntil { gate.callCount >= 2 }
        gate.fireOldest()
        await waitUntil(maxIterations: 300) { presenter.toast == nil }

        #expect(presenter.toast?.message == "B")
    }

    // MARK: - retry()

    @Test("retry() runs the stored closure and dismisses the toast")
    func retryRunsClosureAndDismisses() async {
        let gate = SleepGate()
        let retrySpy = RetrySpy()
        let presenter = ErrorPresenter(sleep: { duration in await gate.sleep(duration) }, announce: { _ in })

        presenter.present("Couldn't save.", retry: { await retrySpy.run() })
        await presenter.retry()

        #expect(retrySpy.ranCount == 1)
        #expect(presenter.toast == nil)
    }

    @Test("retry() dismisses before running the retry closure")
    func retryDismissesBeforeRunningClosure() async {
        let gate = SleepGate()
        var toastWasNilDuringRetry = false
        let presenter = ErrorPresenter(sleep: { duration in await gate.sleep(duration) }, announce: { _ in })

        presenter.present("Couldn't save.", retry: {
            toastWasNilDuringRetry = (presenter.toast == nil)
        })
        await presenter.retry()

        #expect(toastWasNilDuringRetry)
    }

    @Test("retry() is a no-op when no retry closure was provided")
    func retryNoOpWithoutClosure() async {
        let gate = SleepGate()
        let presenter = ErrorPresenter(sleep: { duration in await gate.sleep(duration) }, announce: { _ in })

        presenter.present("Couldn't save.")
        await presenter.retry()

        #expect(presenter.toast != nil)
    }

    @Test("presenting a second toast before the first auto-dismisses replaces its retry closure")
    func secondPresentReplacesFirstRetryClosure() async {
        let gate = SleepGate()
        let retrySpyA = RetrySpy()
        let retrySpyB = RetrySpy()
        let presenter = ErrorPresenter(sleep: { duration in await gate.sleep(duration) }, announce: { _ in })

        presenter.present("A", retry: { await retrySpyA.run() })
        presenter.present("B", retry: { await retrySpyB.run() })
        await presenter.retry()

        #expect(retrySpyB.ranCount == 1)
        #expect(retrySpyA.ranCount == 0)
    }

    // MARK: - announce seam (repeat presentation)

    @Test("presenting a second message announces again, in order")
    func secondPresentAnnouncesAgain() async {
        let gate = SleepGate()
        let spy = AnnounceSpy()
        let presenter = ErrorPresenter(sleep: { duration in await gate.sleep(duration) }, announce: { spy.record($0) })

        presenter.present("First error.")
        presenter.present("Second error.")

        #expect(spy.messages == ["First error.", "Second error."])
    }

    // MARK: - autoDismiss forwarding

    @Test("autoDismiss is forwarded to the sleep seam verbatim, not hardcoded")
    func autoDismissDurationIsForwarded() async {
        let gate = SleepGate()
        let presenter = ErrorPresenter(
            autoDismiss: .seconds(10),
            sleep: { duration in await gate.sleep(duration) },
            announce: { _ in }
        )

        presenter.present("Couldn't save.")

        await waitUntil { gate.callCount >= 1 }
        #expect(gate.durations == [.seconds(10)])
    }
}
