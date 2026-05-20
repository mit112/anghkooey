import Foundation
import SwiftData

/// A persisted flashcard with FSRS-6 scheduling state and review history.
///
/// `stability`, `difficulty`, `dueAt`, and `lastReviewedAt` are owned by the
/// scheduler (see `AnghkooeyCore.Scheduling` in M1 T4); persistence only
/// stores them. Field names and types are pinned by the M1 schema contract.
@Model
public final class Card {
    /// Stable identifier; primary key.
    @Attribute(.unique) public var id: UUID

    /// The prompt shown to the learner.
    public var question: String

    /// The answer revealed during review.
    public var answer: String

    /// Wall-clock time the card was first persisted.
    public var createdAt: Date

    /// Wall-clock time the card's content (`question`/`answer`/`tags`) was last edited.
    public var updatedAt: Date

    /// Tags assigned to this card. Many-to-many; the inverse lives on `Tag.cards`.
    public var tags: [Tag]

    /// Current FSRS lifecycle state.
    public var state: CardState

    /// FSRS-6 stability parameter (days of expected recall after the last review).
    public var stability: Double

    /// FSRS-6 difficulty parameter (intrinsic per-card hardness, 1...10).
    public var difficulty: Double

    /// Next scheduled review time.
    public var dueAt: Date

    /// Wall-clock time of the most recent review; `nil` until the first review.
    public var lastReviewedAt: Date?

    /// Review history for this card. Cascade-deletes with the card.
    @Relationship(deleteRule: .cascade, inverse: \ReviewLog.card)
    public var reviewLogs: [ReviewLog]

    /// Optional excerpt of the source material this card was generated from.
    /// Retained for traceability; not rendered in v1.
    public var sourceSpan: String?

    /// Creates a card with default FSRS state suitable for a brand-new card.
    public init(
        id: UUID = UUID(),
        question: String,
        answer: String,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        tags: [Tag] = [],
        state: CardState = .new,
        stability: Double = 0,
        difficulty: Double = 0,
        dueAt: Date = .now,
        lastReviewedAt: Date? = nil,
        reviewLogs: [ReviewLog] = [],
        sourceSpan: String? = nil
    ) {
        self.id = id
        self.question = question
        self.answer = answer
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.tags = tags
        self.state = state
        self.stability = stability
        self.difficulty = difficulty
        self.dueAt = dueAt
        self.lastReviewedAt = lastReviewedAt
        self.reviewLogs = reviewLogs
        self.sourceSpan = sourceSpan
    }
}
