import Foundation

/// Payload describing a single review event, captured at the moment the
/// engine applied the user's rating.
///
/// Field names mirror the persistence-layer `ReviewLog` (`stateBefore`,
/// `stabilityBefore`, …) so the mapping at the persistence boundary is a
/// straight copy — no rename gymnastics. Values are the pre-review snapshot
/// of the card; the post-review state lives on `SchedulerOutput.card`.
public struct ReviewLogEntry: Equatable, Sendable {
    /// Rating the user submitted.
    public let rating: Rating

    /// Card state immediately before this review was applied.
    public let stateBefore: CardState

    /// Card stability immediately before this review was applied.
    public let stabilityBefore: Double

    /// Card difficulty immediately before this review was applied.
    public let difficultyBefore: Double

    /// Days between the previous review and this one. Zero on first review.
    public let elapsedDays: Double

    /// Integer-day interval the card had been scheduled for prior to this
    /// review.
    public let scheduledDays: Double

    /// Wall-clock instant the review was applied.
    public let reviewedAt: Date

    public init(
        rating: Rating,
        stateBefore: CardState,
        stabilityBefore: Double,
        difficultyBefore: Double,
        elapsedDays: Double,
        scheduledDays: Double,
        reviewedAt: Date
    ) {
        self.rating = rating
        self.stateBefore = stateBefore
        self.stabilityBefore = stabilityBefore
        self.difficultyBefore = difficultyBefore
        self.elapsedDays = elapsedDays
        self.scheduledDays = scheduledDays
        self.reviewedAt = reviewedAt
    }
}

/// Result of applying a rating to a `SchedulingCard`.
///
/// The two halves are returned together so the persistence layer can write
/// the updated `Card` row and the new `ReviewLog` row in a single
/// transaction — partial writes would corrupt the schedule.
public struct SchedulerOutput: Equatable, Sendable {
    /// Card state after the review has been applied.
    public let card: SchedulingCard
    /// Pre-review snapshot recorded for audit / history.
    public let log: ReviewLogEntry

    public init(card: SchedulingCard, log: ReviewLogEntry) {
        self.card = card
        self.log = log
    }
}
