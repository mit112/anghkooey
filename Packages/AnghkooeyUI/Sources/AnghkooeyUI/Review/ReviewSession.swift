import Foundation
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
        // Implementation: Codex M4.7
        fatalError("ReviewSession.loadDueQueue — awaiting Codex M4.7 implementation")
    }

    /// Reveals the answer for the current card.
    public func revealAnswer() {
        // Implementation: Codex M4.7
        fatalError("ReviewSession.revealAnswer — awaiting Codex M4.7 implementation")
    }

    /// Grades the current card and advances to the next, or moves to `.empty`.
    public func submit(grade: ReviewGrade) async {
        // Implementation: Codex M4.7
        fatalError("ReviewSession.submit — awaiting Codex M4.7 implementation")
    }
}
