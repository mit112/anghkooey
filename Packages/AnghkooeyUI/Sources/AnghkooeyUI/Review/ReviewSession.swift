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

    /// Total due cards at last `loadDueQueue` call, before Cushion cap applied.
    /// Use this to render honest copy: "Showing today's batch — N of `backlogTotal` due".
    public private(set) var backlogTotal: Int = 0

    /// True when the visible queue was capped by Cushion Mode at last load.
    public private(set) var isCushionActive: Bool = false

    /// The mnemonic for the current card, or nil if none has been generated yet.
    public private(set) var currentMnemonic: String?

    /// True while `generateMnemonic()` is in flight.
    public private(set) var isMnemonicLoading: Bool = false

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

    private let store: any CardStoreProtocol
    private let scheduler: any FSRS6Engine
    private let clock: @Sendable () -> Date
    private var queue: [Card.Snapshot] = []
    private let mnemonicService: (any MnemonicService)?

    // MARK: Init

    public init(
        store: any CardStoreProtocol,
        scheduler: any FSRS6Engine,
        clock: @Sendable @escaping () -> Date = { .now },
        dailyBatchCap: Int = 20,
        backlogThreshold: Int = 50,
        mnemonicService: (any MnemonicService)? = nil
    ) {
        self.store = store
        self.scheduler = scheduler
        self.clock = clock
        self.dailyBatchCap = dailyBatchCap
        self.backlogThreshold = backlogThreshold
        self.mnemonicService = mnemonicService
    }

    // MARK: Public API

    /// Fetches all due cards, applies Cushion Mode cap if backlog exceeds threshold,
    /// and seeds the review queue.
    public func loadDueQueue() async {
        state = .loading
        do {
            let allDue = try await store.dueCards(asOf: clock())
            backlogTotal = allDue.count
            isCushionActive = allDue.count > backlogThreshold && allDue.count > dailyBatchCap
            let visible = isCushionActive ? Array(allDue.prefix(dailyBatchCap)) : allDue
            queue = Array(visible.dropFirst())
            currentCard = visible.first
            queueRemaining = queue.count
            isAnswerRevealed = false
            state = visible.isEmpty ? .empty : .reviewing
            currentMnemonic = currentCard?.mnemonic
            isMnemonicLoading = false
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    /// Reveals the answer for the current card.
    public func revealAnswer() {
        guard !isAnswerRevealed else { return }
        isAnswerRevealed = true
    }

    /// Grades the current card and advances to the next, or moves to `.empty`.
    public func submit(grade: ReviewGrade) async {
        guard let card = currentCard else { return }
        let signposter = CoreLog.poiSignposter
        let signpostID = signposter.makeSignpostID()
        let intervalState = signposter.beginInterval("review-tap", id: signpostID)
        defer { signposter.endInterval("review-tap", intervalState) }
        do {
            let output = try scheduler.next(
                card: card.schedulingCard,
                rating: grade.fsrsRating,
                now: clock()
            )
            try await store.apply(output, to: card.id, grade: grade.fsrsRating, now: clock())
        } catch {
            // Scheduling errors are non-fatal; advance queue regardless.
        }
        if queue.isEmpty {
            currentCard = nil
            queueRemaining = 0
            state = .empty
            currentMnemonic = nil
            isMnemonicLoading = false
        } else {
            currentCard = queue.removeFirst()
            queueRemaining = queue.count
            isAnswerRevealed = false
            currentMnemonic = currentCard?.mnemonic
            isMnemonicLoading = false
        }
    }

    /// Calls `mnemonicService` to generate a mnemonic for the current card,
    /// then persists it via `store.updateMnemonic`. Non-fatal on error.
    public func generateMnemonic() async {
        guard let card = currentCard, let service = mnemonicService else { return }
        guard !isMnemonicLoading else { return }
        isMnemonicLoading = true
        do {
            let text = try await service.generateMnemonic(
                question: card.question,
                answer: card.answer
            )
            currentMnemonic = text
            try? await store.updateMnemonic(id: card.id, mnemonic: text)
        } catch {
            // Non-fatal: generation failure leaves the button visible to retry.
        }
        isMnemonicLoading = false
    }

    /// Saves in-session edits to the current card's question, answer, and tags.
    ///
    /// Updates the store and refreshes the in-memory snapshot so `ReviewView`
    /// reflects the edit immediately. Non-fatal: a store error leaves the
    /// review queue unaffected.
    public func submitEdit(question: String, answer: String, tags: [String]) async {
        guard let card = currentCard else { return }
        do {
            try await store.update(id: card.id, question: question, answer: answer, tags: tags)
            currentCard = Card.Snapshot(
                id: card.id,
                question: question,
                answer: answer,
                sourceSpan: card.sourceSpan,
                tags: tags,
                state: card.state,
                stability: card.stability,
                difficulty: card.difficulty,
                dueAt: card.dueAt,
                lastReviewedAt: card.lastReviewedAt,
                reps: card.reps,
                lapses: card.lapses,
                learningSteps: card.learningSteps,
                scheduledDays: card.scheduledDays,
                elapsedDays: card.elapsedDays,
                mnemonic: card.mnemonic
            )
        } catch {
            // Non-fatal — leave queue unaffected.
        }
    }
}
