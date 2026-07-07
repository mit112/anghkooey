import Testing
import Foundation
@testable import Anghkooey
import AnghkooeyCore
import AnghkooeyIntelligence
import AnghkooeyUI

// MARK: - #20 regression coverage
//
// `AppState.acceptDraft` used to advance the sheet, fire a detached
// persistence `Task`, and post `.anghkooeyCardAccepted` *synchronously* —
// before the create `Task` had actually run. `ReviewScreen` reloads its due
// queue on that notification, so the reload could race the save and a
// failed save had no visible trace beyond an OSLog line. These tests pin
// the fix: the notification only fires once the card exists in the store,
// and a failed save re-enqueues the draft (never dropping it) and surfaces
// the failure via `errorPresenter`.

/// Reference-type box for state mutated from a `NotificationCenter`
/// observer closure. Mirrors `ClockBox` in
/// `ReviewSessionErrorHandlingTests` — a plain captured `var` can't be
/// mutated from an `@Sendable` observer closure under strict concurrency.
private final class ObservationBox: @unchecked Sendable {
    var notificationFired = false
    var cardCountAtNotification: Int?
}

@Suite("AppState.acceptDraft — #20 ordering and failure handling")
@MainActor
struct AppStateAcceptDraftOrderingTests {

    // MARK: notificationFiresAfterCardExists

    @Test("anghkooeyCardAccepted fires only after the card is persisted")
    func notificationFiresAfterCardExists() async throws {
        let draft = CardDraft(question: "What is 2+2?", answer: "4")
        let mockAuthor = MockCardAuthoringService(drafts: [draft])
        let mockStore = MockCardStore()
        let sut = AppState(cardAuthor: mockAuthor, cardStore: mockStore)

        await sut.enqueue(resolvedText: "2+2=4")
        _ = try #require(sut.presentedDraft)

        let box = ObservationBox()
        let observer = NotificationCenter.default.addObserver(
            forName: .anghkooeyCardAccepted, object: nil, queue: nil
        ) { _ in
            box.notificationFired = true
            box.cardCountAtNotification = mockStore.cards.count
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        // A single await is sufficient: acceptDraft is now async and only
        // returns (and only posts the notification) after the create has
        // landed — no bounded-poll de-flake needed.
        await sut.acceptDraft()

        #expect(box.notificationFired == true)
        #expect(box.cardCountAtNotification == 1)
        #expect(mockStore.cards.first?.question == "What is 2+2?")
        #expect(mockStore.cards.first?.answer == "4")
    }

    // MARK: failedCreateReEnqueuesAndSurfacesError

    @Test("a failed create re-presents the draft, surfaces an error, and does not post the notification")
    func failedCreateReEnqueuesAndSurfacesError() async throws {
        let draft = CardDraft(question: "What is the capital of France?", answer: "Paris")
        let mockAuthor = MockCardAuthoringService(drafts: [draft])
        let mockStore = MockCardStore()
        mockStore.createError = PersistenceError.containerCreationFailed(underlying: NSError(domain: "test", code: 1))
        let sut = AppState(cardAuthor: mockAuthor, cardStore: mockStore)

        await sut.enqueue(resolvedText: "France's capital is Paris.")
        _ = try #require(sut.presentedDraft)

        let box = ObservationBox()
        let observer = NotificationCenter.default.addObserver(
            forName: .anghkooeyCardAccepted, object: nil, queue: nil
        ) { _ in
            box.notificationFired = true
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        await sut.acceptDraft()

        // Nothing silently dropped: the store never saw the card, no
        // notification fired, and the user is told via the error presenter.
        #expect(mockStore.cards.isEmpty)
        #expect(box.notificationFired == false)
        #expect(sut.errorPresenter.toast != nil)

        // The queue was otherwise empty, so the draft is re-presented
        // immediately rather than being lost.
        let rePresented = try #require(sut.presentedDraft)
        #expect(rePresented.draft.question == "What is the capital of France?")
        #expect(rePresented.draft.answer == "Paris")
    }

    // MARK: failedCreateReinsertsAtHeadOfPendingQueue

    @Test("a failed create re-inserts the draft ahead of already-queued drafts")
    func failedCreateReinsertsAtHeadOfPendingQueue() async throws {
        let d1 = CardDraft(question: "Q1", answer: "A1")
        let d2 = CardDraft(question: "Q2", answer: "A2")
        let mockStore = MockCardStore()
        let sut = AppState(cardAuthor: MockCardAuthoringService(drafts: [d1, d2]), cardStore: mockStore)

        await sut.enqueue(resolvedText: "text1")
        await sut.enqueue(resolvedText: "text2")
        let first = try #require(sut.presentedDraft)
        #expect(first.draft.question == "Q1")

        mockStore.createError = PersistenceError.containerCreationFailed(underlying: NSError(domain: "test", code: 1))
        await sut.acceptDraft()

        // d1 failed; presentedDraft moved on to d2 (the queue already had a
        // next item, so no idle re-present happens).
        let second = try #require(sut.presentedDraft)
        #expect(second.draft.question == "Q2")
        #expect(mockStore.cards.isEmpty)
        #expect(sut.errorPresenter.toast != nil)

        // Skipping d2 must surface d1 next — proving d1 was re-queued at the
        // *head* of pendingDrafts, ahead of nothing else pending.
        sut.skipDraft()
        let third = try #require(sut.presentedDraft)
        #expect(third.draft.question == "Q1")
    }

    // MARK: retrySucceedsAfterTransientFailure

    @Test("retrying a failed accept re-creates the same card and posts the notification")
    func retrySucceedsAfterTransientFailure() async throws {
        let draft = CardDraft(question: "What is 2+2?", answer: "4")
        let mockStore = MockCardStore()
        mockStore.createError = PersistenceError.containerCreationFailed(underlying: NSError(domain: "test", code: 1))
        let sut = AppState(cardAuthor: MockCardAuthoringService(drafts: [draft]), cardStore: mockStore)

        await sut.enqueue(resolvedText: "2+2=4")
        await sut.acceptDraft()
        #expect(mockStore.cards.isEmpty)
        #expect(sut.errorPresenter.toast != nil)

        let box = ObservationBox()
        let observer = NotificationCenter.default.addObserver(
            forName: .anghkooeyCardAccepted, object: nil, queue: nil
        ) { _ in box.notificationFired = true }
        defer { NotificationCenter.default.removeObserver(observer) }

        mockStore.createError = nil
        await sut.errorPresenter.retry()

        #expect(mockStore.cards.count == 1)
        #expect(mockStore.cards.first?.question == "What is 2+2?")
        #expect(sut.errorPresenter.toast == nil)
        #expect(sut.presentedDraft == nil)
        #expect(box.notificationFired == true)
    }

    // MARK: successAfterFailureDismissesStaleToastAndPreventsDuplicateCard

    @Test("a success after a prior failure dismisses the stale toast, and the stale retry no-ops instead of duplicating the card")
    func successAfterFailureDismissesStaleToastAndPreventsDuplicateCard() async throws {
        let draft = CardDraft(question: "What is 2+2?", answer: "4")
        let mockStore = MockCardStore()
        mockStore.createError = PersistenceError.containerCreationFailed(underlying: NSError(domain: "test", code: 1))
        let sut = AppState(cardAuthor: MockCardAuthoringService(drafts: [draft]), cardStore: mockStore)

        await sut.enqueue(resolvedText: "2+2=4")

        // First attempt fails: toast (with a live retry closure) is shown,
        // and the draft is re-presented since the queue was otherwise empty.
        await sut.acceptDraft()
        #expect(mockStore.cards.isEmpty)
        #expect(sut.errorPresenter.toast != nil)
        _ = try #require(sut.presentedDraft)

        // The transient condition clears, and the user simply re-Accepts the
        // re-presented sheet — this is a fresh `acceptDraft`, not a retry.
        mockStore.createError = nil
        await sut.acceptDraft()

        // Fix 1: success dismisses the stale toast from the earlier failure.
        #expect(mockStore.cards.count == 1)
        #expect(sut.errorPresenter.toast == nil)

        // Regression guard: if the stale toast's Retry were somehow still
        // tapped after this success, it must not create a second card.
        // `dismiss()` clears the stored retry closure, so this is a no-op.
        await sut.errorPresenter.retry()
        #expect(mockStore.cards.count == 1)
    }
}
