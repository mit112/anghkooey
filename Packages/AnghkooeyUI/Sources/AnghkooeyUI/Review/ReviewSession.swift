import Foundation
import OSLog
import AnghkooeyCore

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

    // MARK: Private

    private let store: any CardStoreProtocol
    private let scheduler: any FSRS6Engine
    private let clock: @Sendable () -> Date
    private var queue: [Card.Snapshot] = []

    // MARK: Init

    public init(
        store: any CardStoreProtocol,
        scheduler: any FSRS6Engine,
        clock: @Sendable @escaping () -> Date = { .now }
    ) {
        self.store = store
        self.scheduler = scheduler
        self.clock = clock
    }

    // MARK: Public API

    /// Fetches all due cards and seeds the review queue.
    public func loadDueQueue() async {
        state = .loading
        do {
            let cards = try await store.dueCards(asOf: clock())
            queue = Array(cards.dropFirst())
            currentCard = cards.first
            queueRemaining = queue.count
            isAnswerRevealed = false
            state = cards.isEmpty ? .empty : .reviewing
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
        } else {
            currentCard = queue.removeFirst()
            queueRemaining = queue.count
            isAnswerRevealed = false
        }
    }
}
