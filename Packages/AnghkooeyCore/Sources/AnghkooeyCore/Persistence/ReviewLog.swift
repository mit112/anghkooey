import Foundation
import SwiftData

/// A persisted record of one card review.
///
/// `*Before` snapshots are captured at the moment of review so the FSRS parity
/// harness can replay the scheduler from any historical point.
@Model
public final class ReviewLog {
    /// Stable identifier; primary key.
    @Attribute(.unique) public var id: UUID

    /// The card this review belongs to. Inverse of `Card.reviewLogs`.
    public var card: Card?

    /// Wall-clock time the user submitted the grade.
    public var reviewedAt: Date

    /// User's grade on this review.
    public var rating: Rating

    /// `Card.state` immediately before this review was applied.
    public var stateBefore: CardState

    /// `Card.stability` immediately before this review was applied.
    public var stabilityBefore: Double

    /// `Card.difficulty` immediately before this review was applied.
    public var difficultyBefore: Double

    /// Days since the prior review at the time this log was recorded.
    public var elapsedDays: Double

    /// The interval the scheduler had picked before this review fired.
    public var scheduledDays: Double

    /// Creates a review log entry. All fields are required; there are no defaults
    /// because every review must be deterministic for parity replay.
    public init(
        id: UUID = UUID(),
        card: Card? = nil,
        reviewedAt: Date,
        rating: Rating,
        stateBefore: CardState,
        stabilityBefore: Double,
        difficultyBefore: Double,
        elapsedDays: Double,
        scheduledDays: Double
    ) {
        self.id = id
        self.card = card
        self.reviewedAt = reviewedAt
        self.rating = rating
        self.stateBefore = stateBefore
        self.stabilityBefore = stabilityBefore
        self.difficultyBefore = difficultyBefore
        self.elapsedDays = elapsedDays
        self.scheduledDays = scheduledDays
    }
}
