import Testing
import Foundation
@testable import Anghkooey
import AnghkooeyCore

// MARK: - #28 regression coverage
//
// `DrainerBridge.didFailItem` used to be a no-op: the `InboxDrainer` had
// already deleted a dropped item's files by the time it called this, so a
// shared screenshot could silently evaporate with zero feedback. Per the
// arbitrated decision (drop-with-message, no retry/schema change — see
// ADR-0003 §9), `AppState` now counts drops for the drain pass in progress
// and reports a single end-of-pass summary via `rootErrorPresenter` rather
// than one toast per dropped item.
//
// `drain()` isn't easily driven end-to-end here without a real
// `InboxDrainer` producing failures, so these tests call the extracted
// `recordDrainFailure` / `beginDrainPass` / `finishDrainPass` seam directly —
// the same seam `drain()` itself calls.

@Suite("AppState drain-failure summary — #28")
@MainActor
struct AppStateDrainFailureTests {

    private struct StubError: Error {}

    // MARK: summaryReportsCorrectDropCount

    @Test("finishDrainPass presents a single summary toast with the correct dropped-item count")
    func summaryReportsCorrectDropCount() {
        let sut = AppState()

        sut.recordDrainFailure(StubError())
        sut.recordDrainFailure(StubError())
        sut.recordDrainFailure(StubError())
        sut.finishDrainPass()

        let toast = sut.rootErrorPresenter.toast
        #expect(toast?.message == "Couldn't read 3 captured item(s). Try sharing them again.")
    }

    // MARK: cleanPassPresentsNoMessage

    @Test("a drain pass with zero failures presents no message")
    func cleanPassPresentsNoMessage() {
        let sut = AppState()

        sut.beginDrainPass()
        sut.finishDrainPass()

        #expect(sut.rootErrorPresenter.toast == nil)
    }

    // MARK: counterResetsPerPass

    @Test("beginDrainPass resets the counter so the next clean pass shows nothing new")
    func counterResetsPerPass() {
        let sut = AppState()

        sut.recordDrainFailure(StubError())
        sut.recordDrainFailure(StubError())
        sut.finishDrainPass()
        #expect(sut.rootErrorPresenter.toast?.message == "Couldn't read 2 captured item(s). Try sharing them again.")

        // The prior toast clears (auto-dismiss, or the user dismissing it)
        // before the next drain pass runs.
        sut.rootErrorPresenter.dismiss()

        // A fresh pass that drops nothing must not resurface a stale count —
        // if the counter weren't reset here, this would re-present "2" again.
        sut.beginDrainPass()
        sut.finishDrainPass()
        #expect(sut.rootErrorPresenter.toast == nil)
    }

    // MARK: singleDropUsesCorrectCount

    @Test("a single dropped item is still reported via the summary path")
    func singleDropUsesCorrectCount() {
        let sut = AppState()

        sut.recordDrainFailure(StubError())
        sut.finishDrainPass()

        #expect(sut.rootErrorPresenter.toast?.message == "Couldn't read 1 captured item(s). Try sharing them again.")
    }

    // MARK: recordDrainFailureIsIndependentOfSheetPresenter

    @Test("recordDrainFailure never touches the sheet-scoped errorPresenter")
    func recordDrainFailureIsIndependentOfSheetPresenter() {
        let sut = AppState()

        sut.recordDrainFailure(StubError())
        sut.finishDrainPass()

        // The two presenters are deliberately separate (see AppState's doc
        // comments on `errorPresenter` vs `rootErrorPresenter`): a drain
        // failure must never surface through the accept-draft sheet toast.
        #expect(sut.errorPresenter.toast == nil)
        #expect(sut.rootErrorPresenter.toast != nil)
    }
}
