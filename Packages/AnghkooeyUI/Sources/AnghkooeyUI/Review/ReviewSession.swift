import Foundation
import OSLog
import AnghkooeyCore
import AnghkooeyIntelligence

// MARK: - ReviewSessionState

public enum ReviewSessionState: Equatable, Sendable {
    case loading
    case reviewing
    case empty
    case error(String)
}

// MARK: - ReviewSessionError

/// Failures raised by `ReviewSession` itself (as opposed to ones surfaced
/// from `CardStoreProtocol` or `MnemonicService`), so callers can tell a
/// local precondition miss apart from a persistence failure.
public enum ReviewSessionError: Error, Sendable, Equatable {
    /// There was no `currentCard` to act on — e.g. the queue emptied or
    /// reloaded while a sheet referencing the old card was still open.
    case noCurrentCard
    /// `currentCard` is non-nil but no longer the card the caller expected
    /// (identified by id) — the queue advanced or reloaded underneath a
    /// still-open edit sheet. Guards against writing an edit to the wrong card.
    case cardChanged
}

// MARK: - ReviewSession

/// `@MainActor @Observable` view model for the card review loop.
///
/// `ReviewSession` owns the in-flight review state: the current due card,
/// whether the answer is revealed, and how many cards remain in the queue.
/// It talks to `CardStoreProtocol` (for fetch and persist) and `FSRS6Engine`
/// (for scheduling) — the `ReviewView` drives it without knowing about either.
@MainActor
@Observable
public final class ReviewSession {

    // MARK: Public state (observed by ReviewView)

    public private(set) var currentCard: Card.Snapshot?
    public private(set) var isAnswerRevealed: Bool = false
    public private(set) var queueRemaining: Int = 0
    public private(set) var state: ReviewSessionState = .loading

    /// Accumulated stats for the current session (reviewed count, accuracy).
    /// Reset each time `loadDueQueue()` seeds a fresh queue.
    public private(set) var summary = ReviewSummary()

    /// Total due cards at last `loadDueQueue` call, before Cushion cap applied.
    /// Use this to render honest copy: "Showing today's batch — N of `backlogTotal` due".
    public private(set) var backlogTotal: Int = 0

    /// True when the visible queue was capped by Cushion Mode at last load.
    public private(set) var isCushionActive: Bool = false

    /// The mnemonic for the current card, or nil if none has been generated yet.
    public private(set) var currentMnemonic: String?

    /// True while `generateMnemonic()` is in flight.
    public private(set) var isMnemonicLoading: Bool = false

    /// Number of cards with FSRS stability ≥ `LTMConfig.defaultThresholdDays`.
    /// Updated alongside the due queue on every `loadDueQueue()` call.
    public private(set) var ltmCount: Int = 0

    /// When the in-session queue empties but a card is known to become due
    /// again soon (e.g. an FSRS learning-step "Again" card), this is that
    /// due date; `nil` when nothing is upcoming. `ReviewView` uses this to
    /// show "next card in ~N min" instead of a bare "all caught up" (#18).
    public private(set) var nextDueDate: Date?

    /// Seconds-until-next-due per `Rating` for the current card.
    /// Empty when there is no current card.
    public var currentIntervals: [Rating: TimeInterval] {
        guard let card = currentCard else { return [:] }
        return IntervalProjection.project(card: card.schedulingCard, engine: scheduler(), now: clock())
    }

    /// Cards remaining in this session including the current card.
    public var remainingCount: Int {
        queueRemaining + (currentCard != nil ? 1 : 0)
    }

    /// Total cards in the store (not just due). Updated in `loadDueQueue()`.
    /// Use to distinguish "nothing due" from "deck is empty".
    public private(set) var totalCardCount: Int = 0

    /// True when a `MnemonicService` was injected — `ReviewView` uses this to
    /// conditionally render the "Generate Mnemonic" button.
    public var isMnemonicAvailable: Bool { mnemonicService != nil }

    // MARK: Cushion configuration

    /// Maximum number of cards shown in a single session when cushion fires.
    /// Default 20 per `foundation.md §4 Grace features`.
    public let dailyBatchCap: Int

    /// When total due cards exceeds this, cushion fires and caps the queue
    /// to `dailyBatchCap`. Default 50 per `foundation.md §4`.
    public let backlogThreshold: Int

    // MARK: Private

    public let store: any CardStoreProtocol
    private let scheduler: () -> any FSRS6Engine
    private let clock: @Sendable () -> Date
    private var queue: [Card.Snapshot] = []
    private let mnemonicService: (any MnemonicService)?

    /// Bumped at the start of every `loadDueQueue()` call. `loadDueQueue()`
    /// and `enterEmptyState(generation:)` each capture the generation that
    /// was current when *they* started and re-check it after every `await`
    /// before writing published state. A load fired from `.task` /
    /// `scenePhase` / `.anghkooeyCardAccepted` (see `ReviewScreen`) can
    /// suspend across an `await`; without this guard, a second concurrent
    /// `loadDueQueue()` that starts and finishes during that suspension
    /// would get clobbered when the first, now-stale call resumes (#18).
    private var loadGeneration = 0

    /// Surfaces persistence/generation failures to the owning screen.
    /// `nil` by default so existing construction sites keep compiling; a
    /// session built without one silently drops errors it can't hand off
    /// (see the `#23` fix — every call site that matters injects one).
    private let errorPresenter: ErrorPresenter?

    /// Test seam for the single scheduled wake in `scheduleNextDueCheck(at:)`.
    /// Defaults to a real `Task.sleep` so existing construction sites need no
    /// change; mirrors `ErrorPresenter`'s `sleep` seam (#22) so tests inject a
    /// controllable stand-in and nothing waits on real time.
    private let sleep: @Sendable (Duration) async -> Void

    /// The single in-flight "wake me when the next learning-step card is
    /// due" task, or `nil` when nothing is scheduled. At most one is ever
    /// outstanding: `scheduleNextDueCheck(at:)` cancels any prior one before
    /// starting a new one, and `loadDueQueue()` cancels it too so a stale
    /// wake from a since-superseded queue load can't double-seed (#18).
    ///
    /// `nonisolated(unsafe)` so `deinit` (which runs nonisolated) can cancel
    /// it — required because the `@Observable` macro's generated backing for
    /// this stored property cannot be plain `nonisolated`. Safe: every other
    /// access is on the MainActor and `deinit` runs with no other references
    /// left to race with.
    nonisolated(unsafe) private var nextDueCheckTask: Task<Void, Never>?

    // MARK: Init

    public init(
        store: any CardStoreProtocol,
        scheduler: @escaping () -> any FSRS6Engine = { LiveFSRS6Engine() },
        clock: @Sendable @escaping () -> Date = { .now },
        sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) },
        dailyBatchCap: Int = 20,
        backlogThreshold: Int = 50,
        mnemonicService: (any MnemonicService)? = nil,
        errorPresenter: ErrorPresenter? = nil
    ) {
        self.store = store
        self.scheduler = scheduler
        self.clock = clock
        self.sleep = sleep
        self.dailyBatchCap = dailyBatchCap
        self.backlogThreshold = backlogThreshold
        self.mnemonicService = mnemonicService
        self.errorPresenter = errorPresenter
    }

    deinit {
        nextDueCheckTask?.cancel()
    }

    // MARK: Public API

    /// Fetches all due cards, applies Cushion Mode cap if backlog exceeds threshold,
    /// and seeds the review queue.
    ///
    /// - Parameter resetSummary: When `true` (the default), resets `summary`
    ///   to a fresh `ReviewSummary()` — this call represents a new sitting.
    ///   The single scheduled wake in `scheduleNextDueCheck(at:)` passes
    ///   `false` instead: a learning-step card reappearing mid-sitting is a
    ///   continuation of the same session, not a new one, so the running
    ///   tally must survive it (#18).
    public func loadDueQueue(resetSummary: Bool = true) async {
        // Cancel and clear any wake scheduled by a prior queue-emptied event
        // — this reload supersedes it, and a stale wake must not fire a
        // second, possibly-conflicting re-seed later (#18).
        nextDueCheckTask?.cancel()
        nextDueCheckTask = nil
        nextDueDate = nil
        state = .loading
        loadGeneration &+= 1
        let gen = loadGeneration
        do {
            // Both throwing fetches happen before any published-state mutation
            // so a failure in either leaves no stale reviewing snapshot behind.
            let allDue = try await store.dueCards(asOf: clock())
            guard gen == loadGeneration else { return } // superseded by a newer load
            let counts = try await store.count(asOf: clock())
            guard gen == loadGeneration else { return }

            backlogTotal = allDue.count
            isCushionActive = allDue.count > backlogThreshold && allDue.count > dailyBatchCap
            let visible = isCushionActive ? Array(allDue.prefix(dailyBatchCap)) : allDue
            queue = Array(visible.dropFirst())
            currentCard = visible.first
            queueRemaining = queue.count
            isAnswerRevealed = false
            if resetSummary {
                summary = ReviewSummary()
            }
            totalCardCount = counts.total
            currentMnemonic = currentCard?.mnemonic
            isMnemonicLoading = false

            // Deliberate non-fatal degrade (not a swallowed error, #23 audit):
            // the LTM banner is a nice-to-have stat, not part of the review
            // contract, so a failure here just keeps showing the prior count
            // rather than surfacing a toast or failing the whole queue load.
            let ltm = try? await store.longTermMemoryCount(thresholdDays: LTMConfig.defaultThresholdDays)
            guard gen == loadGeneration else { return }
            ltmCount = ltm ?? ltmCount

            if visible.isEmpty {
                // Recomputes nextDueDate + wake instead of a bare `.empty` so
                // the ETA/wake survive a reload (e.g. backgrounding then
                // foregrounding while a wake was already pending) instead of
                // being silently dropped (#18).
                await enterEmptyState(generation: gen)
            } else {
                state = .reviewing
            }
        } catch {
            guard gen == loadGeneration else { return }
            UILog.review.error("loadDueQueue failed to fetch the due queue: \(error)")
            state = .error(error.localizedDescription)
        }
    }

    /// Reveals the answer for the current card.
    public func revealAnswer() {
        guard !isAnswerRevealed else { return }
        isAnswerRevealed = true
    }

    /// Grades the current card and advances to the next, or moves to `.empty`.
    ///
    /// On a scheduling or persistence failure, the grade is discarded: the
    /// summary is not recorded and the queue does not advance, so the user
    /// never sees a card as reviewed when the write never landed (#23). The
    /// failure is surfaced via `errorPresenter` with a retry that re-applies
    /// this exact grade to this exact card (see `applyGrade(_:to:)`). On
    /// success, any stale error toast from a previous failure is dismissed.
    public func submit(grade: ReviewGrade) async {
        guard let card = currentCard else { return }
        await applyGrade(grade, to: card)
    }

    /// Does the actual scheduling + persistence work for `submit(grade:)`,
    /// pinned to the exact `card` snapshot the caller already resolved.
    ///
    /// Kept separate from `submit(grade:)` so the retry closure below can
    /// re-apply the same grade to the *same* card even if `currentCard` has
    /// since changed (e.g. `loadDueQueue()` re-fired from a scenePhase or
    /// `.anghkooeyCardAccepted` notification while the error toast was still
    /// showing) — re-reading `currentCard` in the retry could otherwise grade
    /// the wrong card.
    private func applyGrade(_ grade: ReviewGrade, to card: Card.Snapshot) async {
        let signposter = CoreLog.poiSignposter
        let signpostID = signposter.makeSignpostID()
        let intervalState = signposter.beginInterval("review-tap", id: signpostID)
        defer { signposter.endInterval("review-tap", intervalState) }
        do {
            let output = try scheduler().next(
                card: card.schedulingCard,
                rating: grade.fsrsRating,
                now: clock()
            )
            try await store.apply(output, to: card.id, grade: grade.fsrsRating, now: clock())
        } catch {
            UILog.review.error("submit(grade:) failed to save the review: \(error)")
            errorPresenter?.present(
                "Couldn't save your grade — try again.",
                retry: { [weak self] in
                    guard let self else { return }
                    await self.applyGrade(grade, to: card)
                }
            )
            return
        }
        // The store write for `card` has landed — that's correct and must
        // not be undone. But a concurrent `loadDueQueue()` (scenePhase /
        // `.anghkooeyCardAccepted` / the #18 wake) can have changed
        // `currentCard` while the write above was in flight. If it has, the
        // reload already owns the current session state: recording into the
        // (possibly reset) summary or dequeuing the (now-different) live
        // queue here would advance/drop the wrong card.
        guard currentCard?.id == card.id else { return }
        errorPresenter?.dismiss()
        summary.record(grade.fsrsRating)
        if queue.isEmpty {
            currentCard = nil
            queueRemaining = 0
            currentMnemonic = nil
            isMnemonicLoading = false
            await enterEmptyState(generation: loadGeneration)
        } else {
            currentCard = queue.removeFirst()
            queueRemaining = queue.count
            isAnswerRevealed = false
            currentMnemonic = currentCard?.mnemonic
            isMnemonicLoading = false
        }
    }

    /// Enters the empty state, but first computes the next due time so the
    /// UI can show an ETA and a single wake can re-seed the queue when a
    /// learning-step (Again) card becomes due. Called both when
    /// `loadDueQueue()` finds nothing visible and when `submit(grade:)`
    /// empties the queue mid-session (#18).
    ///
    /// Deliberately does **not** re-fetch `dueCards(asOf:)` and dump
    /// whatever it finds into the queue: the only thing that query can
    /// return right after the queue just emptied is Cushion-Mode-held
    /// backlog beyond `dailyBatchCap`, and Cushion Mode's contract is one
    /// capped batch per load — re-seeding that backlog here, even re-capped,
    /// would defeat the feature. Learning-step ("Again") cards are due in
    /// the *future*, not now, so they're handled by the scheduled wake
    /// below, never by an immediate re-seed.
    ///
    /// `generation` pins this call to the `loadDueQueue()` (or
    /// `submit(grade:)`) invocation that started it. If a newer
    /// `loadDueQueue()` has since bumped `loadGeneration` by the time the
    /// `await` below resumes, this call has been superseded and must not
    /// clobber the newer call's state (#18).
    ///
    /// A fetch failure logs and falls back to a plain `.empty` with no
    /// next-due marker — a deliberate, documented safe fallback (not a
    /// silent `try?`, per #23's no-silent-swallow rule): the user still
    /// sees "all caught up" rather than a stuck spinner, they just lose
    /// the ETA.
    ///
    /// Note: the ETA/wake computed here account only for FSRS `dueAt`, not
    /// `clozeBuriedUntil` expiry — cloze burial clears at the next calendar
    /// day, not a minutes-scale learning step, so it's intentionally out of
    /// #18's scope and is instead picked up by the next foreground
    /// `loadDueQueue()`.
    private func enterEmptyState(generation: Int) async {
        do {
            let next = try await store.nextDueDate(after: clock())
            guard generation == loadGeneration else { return } // superseded
            currentCard = nil
            queueRemaining = 0
            currentMnemonic = nil
            isMnemonicLoading = false
            nextDueDate = next
            state = .empty
            if let next {
                await scheduleNextDueCheck(at: next)
            }
        } catch {
            guard generation == loadGeneration else { return }
            UILog.review.error("re-check after queue emptied failed: \(error)")
            nextDueDate = nil
            state = .empty
        }
    }

    /// Schedules exactly one wake at `date` to re-check the due queue —
    /// never a polling loop. Cancels any previously-scheduled wake first, so
    /// at most one is ever outstanding (#18).
    private func scheduleNextDueCheck(at date: Date) async {
        nextDueCheckTask?.cancel()
        let delay = date.timeIntervalSince(clock())
        guard delay > 0 else {
            // Already due by the time we got here (e.g. clock crossed it
            // between the two fetches above) — just reload now. `false`:
            // this re-seed continues the current sitting (#18 finding 3).
            nextDueCheckTask = nil
            await loadDueQueue(resetSummary: false)
            return
        }
        nextDueCheckTask = Task { @MainActor [weak self] in
            await self?.sleep(.seconds(delay))
            guard !Task.isCancelled, let self else { return }
            // `false`: the wake continues the current sitting, so the
            // running summary must survive the re-seed (#18 finding 3).
            await self.loadDueQueue(resetSummary: false) // re-seed; the now-due card reappears
        }
    }

    /// Calls `mnemonicService` to generate a mnemonic for the current card,
    /// then persists it via `store.updateMnemonic`.
    ///
    /// Generation and persistence failures are surfaced separately (#23): a
    /// generation failure never sets `currentMnemonic` and offers a retry
    /// that regenerates; a persistence failure keeps the already-generated
    /// mnemonic on screen (it did generate) but warns it won't be kept, with
    /// a retry that re-attempts only the save.
    public func generateMnemonic() async {
        guard let card = currentCard, let service = mnemonicService else { return }
        guard !isMnemonicLoading else { return }
        await generateMnemonic(for: card, using: service)
    }

    /// Does the actual generate-then-persist work for `generateMnemonic()`,
    /// pinned to the `card`/`service` pair the caller already resolved, so a
    /// regenerate-retry targets the same card even if `currentCard` has since
    /// changed underneath the toast (see `applyGrade(_:to:)` for the same
    /// reasoning on the grading path).
    private func generateMnemonic(for card: Card.Snapshot, using service: any MnemonicService) async {
        isMnemonicLoading = true
        defer { isMnemonicLoading = false }

        let text: String
        do {
            text = try await service.generateMnemonic(
                question: card.question,
                answer: card.answer
            )
        } catch {
            UILog.review.error("generateMnemonic failed to generate: \(error)")
            errorPresenter?.present(
                "Couldn't generate a mnemonic — try again.",
                retry: { [weak self] in
                    guard let self else { return }
                    await self.generateMnemonic(for: card, using: service)
                }
            )
            return
        }
        // If the user advanced to a different card while generation was in
        // flight, this mnemonic is stale — discard it rather than publish it
        // onto (or persist it against) whatever card is current now.
        guard currentCard?.id == card.id else { return }
        currentMnemonic = text
        await persistMnemonic(text, for: card.id)
    }

    /// Persists a generated mnemonic, surfacing (and offering to retry) a
    /// failure without touching the already-displayed `currentMnemonic`. On
    /// success, dismisses any stale error toast so a lingering retry from a
    /// prior failure can't later be re-applied to a different card.
    private func persistMnemonic(_ text: String, for cardID: UUID) async {
        do {
            try await store.updateMnemonic(id: cardID, mnemonic: text)
        } catch {
            UILog.review.error("generateMnemonic failed to persist the mnemonic: \(error)")
            errorPresenter?.present(
                "Couldn't save the mnemonic; it won't be kept.",
                retry: { [weak self] in
                    guard let self else { return }
                    await self.persistMnemonic(text, for: cardID)
                }
            )
            return
        }
        errorPresenter?.dismiss()
    }

    /// Saves in-session edits to the card identified by `cardID` — the id of
    /// the card the edit sheet was opened for, not just "whatever
    /// `currentCard` happens to be right now".
    ///
    /// Updates the store and refreshes the in-memory snapshot so `ReviewView`
    /// reflects the edit immediately. On a store failure, the in-memory
    /// snapshot is left untouched and the error is rethrown (#23) so the
    /// caller (the edit sheet) can keep the sheet open and the entered text.
    ///
    /// Throws instead of silently no-op'ing (a prior bug) when there is no
    /// current card, or when `currentCard` no longer matches `cardID` — both
    /// can happen because `loadDueQueue()` re-fires on `scenePhase == .active`
    /// and on `.anghkooeyCardAccepted` while the edit sheet is still open, so
    /// the queue can advance or reload underneath it. Without this check, the
    /// edit would either silently vanish or land on the wrong card.
    public func submitEdit(cardID: UUID, question: String, answer: String, tags: [String]) async throws {
        guard let card = currentCard else {
            throw ReviewSessionError.noCurrentCard
        }
        guard card.id == cardID else {
            throw ReviewSessionError.cardChanged
        }
        let saved: Card.Snapshot?
        do {
            saved = try await store.update(id: card.id, question: question, answer: answer, tags: tags)
        } catch {
            UILog.review.error("submitEdit failed to save the card: \(error)")
            throw error
        }
        // The edit persisted to `cardID` regardless — that's correct and
        // must not be rethrown. But a concurrent `loadDueQueue()` can have
        // changed `currentCard` while the write above was in flight; if it
        // has, the reload owns the current state and this must not clobber it.
        guard currentCard?.id == cardID, let saved else { return }
        errorPresenter?.dismiss()
        // Use the store's persisted snapshot — its tag names are canonicalized
        // (case-insensitive dedupe, first-writer casing), so rebuilding from the
        // input `tags` would show casing the store didn't actually keep (#54).
        currentCard = saved
    }
}
