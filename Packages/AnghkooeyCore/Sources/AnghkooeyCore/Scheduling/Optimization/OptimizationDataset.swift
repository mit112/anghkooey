import Foundation

/// Replay-based training dataset built from a user's review history.
///
/// Groups rows by card, sorts each group chronologically, caps to
/// `maxSequenceLength` keeping the most recent, then maps to `ReviewSample`.
/// Same-day semantics match py-fsrs: `sameDay = (elapsedDays == 0)`.
public struct OptimizationDataset: Sendable, Equatable {
    /// Per-card ordered review sequences. Index 0 in each is the first review.
    public let cardSequences: [[ReviewSample]]

    /// Maximum reviews kept per card. Confirmed against pinned py-fsrs in T2;
    /// provisional value is 200 (keep most-recent N when sequence is longer).
    public static let maxSequenceLength = 200

    /// Build from a flat projection. Rows are grouped by `cardID`, each group
    /// sorted by `reviewedAt`, then capped to `maxSequenceLength` (keep most
    /// recent). `sameDay = (elapsedDays == 0)`.
    public init(rows: [OptimizationReviewLogRow]) {
        let grouped = Dictionary(grouping: rows, by: \.cardID)
        self.cardSequences = grouped.values.map { group in
            let ordered = group.sorted { $0.reviewedAt < $1.reviewedAt }
            let capped = ordered.suffix(Self.maxSequenceLength)
            return capped.map {
                ReviewSample(elapsedDays: $0.elapsedDays, rating: $0.rating, sameDay: $0.elapsedDays == 0)
            }
        }
    }

    /// For test fixtures that inject sequences directly.
    public init(cardSequences: [[ReviewSample]] = []) {
        self.cardSequences = cardSequences
    }

    /// Count of samples that contribute to the loss: non-first (index > 0)
    /// AND non-same-day (`!sameDay`).
    public var eligibleSampleCount: Int {
        cardSequences.reduce(0) { acc, seq in
            acc + seq.enumerated().filter { idx, s in idx > 0 && !s.sameDay }.count
        }
    }
}
