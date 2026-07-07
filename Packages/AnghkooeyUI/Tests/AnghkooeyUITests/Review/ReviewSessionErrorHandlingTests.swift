import Testing
import Foundation
@testable import AnghkooeyUI
import AnghkooeyCore
import AnghkooeyIntelligence

/// Regression coverage for #23: `ReviewSession` used to swallow persistence
/// (and, for mnemonics, generation) failures silently — a failed write left
/// the UI reporting success while the underlying state was never saved.
/// These tests pin the fixed behavior: failures are surfaced via the
/// injected `ErrorPresenter` and never allowed to masquerade as success.
/// Test-only mutable clock box. Lets a test move `now` forward or backward
/// between two `loadDueQueue()` calls on the *same* session (and therefore
/// the same `errorPresenter`), which a plain `{ now }` closure over a `let`
/// can't do — needed to simulate `currentCard` changing while a toast/retry
/// from an earlier failure is still pinned to the original card.
private final class ClockBox: @unchecked Sendable {
    var date: Date
    init(_ date: Date) { self.date = date }
}

@Suite("ReviewSession — #23 swallowed persistence failures")
@MainActor
struct ReviewSessionErrorHandlingTests {

    private func makeSession(
        store: MockCardStore,
        errorPresenter: ErrorPresenter? = nil,
        mnemonicService: (any MnemonicService)? = nil,
        now: Date = Date(timeIntervalSinceReferenceDate: 0)
    ) -> ReviewSession {
        ReviewSession(
            store: store,
            scheduler: { MockFSRS6Engine() },
            clock: { now },
            mnemonicService: mnemonicService,
            errorPresenter: errorPresenter
        )
    }

    @discardableResult
    private func seedCards(
        count: Int,
        in store: MockCardStore,
        now: Date = Date(timeIntervalSinceReferenceDate: 0)
    ) async throws -> [Card.Snapshot] {
        var cards: [Card.Snapshot] = []
        for index in 1...count {
            cards.append(try await store.create(
                question: "Q\(index)",
                answer: "A\(index)",
                sourceSpan: nil,
                now: now
            ))
        }
        return cards
    }

    // MARK: - submit(grade:)

    @Test("submit(grade:) on a failed apply does not advance the queue or record the summary")
    func submitOnFailedApplyDoesNotAdvanceOrRecord() async throws {
        let now = Date(timeIntervalSinceReferenceDate: 0)
        let store = MockCardStore()
        try await seedCards(count: 2, in: store, now: now)
        store.applyError = PersistenceError.invalidShift(days: -1)
        let presenter = ErrorPresenter()
        let session = makeSession(store: store, errorPresenter: presenter, now: now)
        await session.loadDueQueue()
        let firstID = try #require(session.currentCard?.id)

        session.revealAnswer()
        await session.submit(grade: .good)

        #expect(session.currentCard?.id == firstID)
        #expect(session.isAnswerRevealed == true)
        #expect(session.summary.reviewed == 0)
        #expect(presenter.toast != nil)
    }

    @Test("submit(grade:) retry re-runs the same grade against the store")
    func submitRetryReRunsSameGrade() async throws {
        let now = Date(timeIntervalSinceReferenceDate: 0)
        let store = MockCardStore()
        try await seedCards(count: 2, in: store, now: now)
        store.applyError = PersistenceError.invalidShift(days: -1)
        let presenter = ErrorPresenter()
        let session = makeSession(store: store, errorPresenter: presenter, now: now)
        await session.loadDueQueue()

        session.revealAnswer()
        await session.submit(grade: .good)
        #expect(presenter.toast != nil)

        store.applyError = nil
        await presenter.retry()

        #expect(session.summary.reviewed == 1)
        #expect(store.reviewLogs.count == 1)
    }

    @Test("submit(grade:) retry re-applies to the card that failed, not whatever currentCard has since become")
    func submitRetryPinsToOriginallyFailingCard() async throws {
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        let t50 = Date(timeIntervalSinceReferenceDate: 50)
        let t100 = Date(timeIntervalSinceReferenceDate: 100)
        let store = MockCardStore()
        // cardX is created first (so it wins the due-queue's insertion-order
        // tiebreak) but is due later, at t100; cardY is due earlier, at t0.
        let cardX = try await store.create(question: "QX", answer: "AX", sourceSpan: nil, now: t100)
        let cardY = try await store.create(question: "QY", answer: "AY", sourceSpan: nil, now: t0)
        store.applyError = PersistenceError.invalidShift(days: -1)
        let presenter = ErrorPresenter()
        let clockBox = ClockBox(t100)
        let session = ReviewSession(
            store: store,
            scheduler: { MockFSRS6Engine() },
            clock: { clockBox.date },
            errorPresenter: presenter
        )
        await session.loadDueQueue()
        #expect(session.currentCard?.id == cardX.id)

        session.revealAnswer()
        await session.submit(grade: .good)
        #expect(presenter.toast != nil)

        // Simulate a `loadDueQueue()` re-fire (scenePhase/.anghkooeyCardAccepted)
        // while the toast is still up: move the clock so cardX is no longer
        // due but cardY still is — `currentCard` becomes a different card.
        clockBox.date = t50
        await session.loadDueQueue()
        #expect(session.currentCard?.id == cardY.id)

        store.applyError = nil
        await presenter.retry()

        // The retry must have graded cardX — the card that actually failed —
        // never cardY, which only became `currentCard` after the reload.
        #expect(store.reviewLogs.map(\.cardID) == [cardX.id])
    }

    @Test("submit(grade:) success dismisses a stale error toast from a previous failure")
    func submitSuccessDismissesStaleToast() async throws {
        let now = Date(timeIntervalSinceReferenceDate: 0)
        let store = MockCardStore()
        try await seedCards(count: 1, in: store, now: now)
        store.applyError = PersistenceError.invalidShift(days: -1)
        let presenter = ErrorPresenter()
        let session = makeSession(store: store, errorPresenter: presenter, now: now)
        await session.loadDueQueue()

        session.revealAnswer()
        await session.submit(grade: .good)
        #expect(presenter.toast != nil)

        store.applyError = nil
        await session.submit(grade: .good)

        #expect(presenter.toast == nil)
    }

    // MARK: - submitEdit(...)

    @Test("submitEdit throws on a failed store update and leaves currentCard unchanged")
    func submitEditThrowsOnFailedUpdate() async throws {
        let now = Date(timeIntervalSinceReferenceDate: 0)
        let store = MockCardStore()
        try await seedCards(count: 1, in: store, now: now)
        let session = makeSession(store: store, now: now)
        await session.loadDueQueue()
        let before = try #require(session.currentCard)

        store.updateError = PersistenceError.invalidShift(days: -1)

        await #expect(throws: (any Error).self) {
            try await session.submitEdit(cardID: before.id, question: "New Q", answer: "New A", tags: [])
        }
        #expect(session.currentCard == before)
    }

    @Test("submitEdit updates the in-memory snapshot on success")
    func submitEditUpdatesSnapshotOnSuccess() async throws {
        let now = Date(timeIntervalSinceReferenceDate: 0)
        let store = MockCardStore()
        try await seedCards(count: 1, in: store, now: now)
        let session = makeSession(store: store, now: now)
        await session.loadDueQueue()
        let cardID = try #require(session.currentCard?.id)

        try await session.submitEdit(cardID: cardID, question: "New Q", answer: "New A", tags: ["tag"])

        #expect(session.currentCard?.question == "New Q")
        #expect(session.currentCard?.answer == "New A")
        #expect(session.currentCard?.tags == ["tag"])
    }

    @Test("submitEdit throws .noCurrentCard when the session has emptied since the sheet opened")
    func submitEditThrowsNoCurrentCardWhenSessionEmptied() async throws {
        let now = Date(timeIntervalSinceReferenceDate: 0)
        let store = MockCardStore()
        try await seedCards(count: 1, in: store, now: now)
        let session = makeSession(store: store, now: now)
        await session.loadDueQueue()
        let cardID = try #require(session.currentCard?.id)

        // Grade the only card so the queue empties and currentCard goes nil —
        // simulates the edit sheet outliving the card it was opened for.
        session.revealAnswer()
        await session.submit(grade: .good)
        #expect(session.currentCard == nil)

        await #expect(throws: ReviewSessionError.noCurrentCard) {
            try await session.submitEdit(cardID: cardID, question: "New Q", answer: "New A", tags: [])
        }
    }

    @Test("submitEdit throws .cardChanged when currentCard advanced to a different card")
    func submitEditThrowsCardChangedWhenCurrentCardAdvanced() async throws {
        let now = Date(timeIntervalSinceReferenceDate: 0)
        let store = MockCardStore()
        try await seedCards(count: 2, in: store, now: now)
        let session = makeSession(store: store, now: now)
        await session.loadDueQueue()
        let staleCardID = try #require(session.currentCard?.id)

        // Grade the first card so the queue advances to the second — the
        // edit sheet, if still holding the stale id, must not write to it.
        session.revealAnswer()
        await session.submit(grade: .good)
        let newCardID = try #require(session.currentCard?.id)
        #expect(newCardID != staleCardID)

        await #expect(throws: ReviewSessionError.cardChanged) {
            try await session.submitEdit(cardID: staleCardID, question: "New Q", answer: "New A", tags: [])
        }
    }

    @Test("submitEdit success dismisses a stale error toast from a previous grading failure")
    func submitEditSuccessDismissesStaleToast() async throws {
        let now = Date(timeIntervalSinceReferenceDate: 0)
        let store = MockCardStore()
        try await seedCards(count: 1, in: store, now: now)
        store.applyError = PersistenceError.invalidShift(days: -1)
        let presenter = ErrorPresenter()
        let session = makeSession(store: store, errorPresenter: presenter, now: now)
        await session.loadDueQueue()
        let cardID = try #require(session.currentCard?.id)

        session.revealAnswer()
        await session.submit(grade: .good)
        #expect(presenter.toast != nil)

        try await session.submitEdit(cardID: cardID, question: "New Q", answer: "New A", tags: [])

        #expect(presenter.toast == nil)
    }

    // MARK: - generateMnemonic() — persistence failure

    @Test("generateMnemonic on a failed persistence keeps the displayed mnemonic and surfaces the error")
    func generateMnemonicOnFailedPersistenceKeepsDisplayedMnemonic() async throws {
        let now = Date(timeIntervalSinceReferenceDate: 0)
        let store = MockCardStore()
        try await seedCards(count: 1, in: store, now: now)
        store.updateMnemonicError = PersistenceError.invalidShift(days: -1)
        let presenter = ErrorPresenter()
        let service = MockMnemonicService(mnemonic: "Picture a golden gate.")
        let session = makeSession(store: store, errorPresenter: presenter, mnemonicService: service, now: now)
        await session.loadDueQueue()

        await session.generateMnemonic()

        #expect(session.currentMnemonic == "Picture a golden gate.")
        #expect(presenter.toast != nil)
        #expect(session.isMnemonicLoading == false)
    }

    @Test("generateMnemonic persistence retry success dismisses the stale error toast")
    func generateMnemonicPersistenceRetrySuccessDismissesToast() async throws {
        let now = Date(timeIntervalSinceReferenceDate: 0)
        let store = MockCardStore()
        try await seedCards(count: 1, in: store, now: now)
        store.updateMnemonicError = PersistenceError.invalidShift(days: -1)
        let presenter = ErrorPresenter()
        let service = MockMnemonicService(mnemonic: "Picture a golden gate.")
        let session = makeSession(store: store, errorPresenter: presenter, mnemonicService: service, now: now)
        await session.loadDueQueue()

        await session.generateMnemonic()
        #expect(presenter.toast != nil)

        store.updateMnemonicError = nil
        await presenter.retry()

        #expect(presenter.toast == nil)
    }

    // MARK: - generateMnemonic() — generation failure

    @Test("generateMnemonic on a failed generation surfaces the error and stops loading")
    func generateMnemonicOnFailedGenerationSurfacesError() async throws {
        struct GenerationError: Error {}
        let now = Date(timeIntervalSinceReferenceDate: 0)
        let store = MockCardStore()
        try await seedCards(count: 1, in: store, now: now)
        let presenter = ErrorPresenter()
        let service = MockMnemonicService(error: GenerationError())
        let session = makeSession(store: store, errorPresenter: presenter, mnemonicService: service, now: now)
        await session.loadDueQueue()

        await session.generateMnemonic()

        #expect(presenter.toast != nil)
        #expect(session.isMnemonicLoading == false)
        #expect(session.currentMnemonic == nil)
    }
}
