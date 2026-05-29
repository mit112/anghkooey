import Foundation

/// Narrow value-type projection of one `ReviewLog`, produced by
/// `CardStoreProtocol.optimizationReviewLogs()`. Carries only the four fields
/// the dataset needs so the fetch never walks full `Card` graphs.
public struct OptimizationReviewLogRow: Equatable, Sendable {
    public let cardID: UUID
    public let reviewedAt: Date
    public let rating: Rating
    public let elapsedDays: Double

    public init(cardID: UUID, reviewedAt: Date, rating: Rating, elapsedDays: Double) {
        self.cardID = cardID
        self.reviewedAt = reviewedAt
        self.rating = rating
        self.elapsedDays = elapsedDays
    }
}
