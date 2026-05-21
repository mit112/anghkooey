import Foundation

/// Lifecycle state of a card under the FSRS-6 scheduler.
///
/// Raw values are pinned (`Int`) so future schema migrations can detect drift —
/// changing a raw value here is a breaking change that requires a `MigrationStage`.
public enum CardState: Int, Codable, Sendable, CaseIterable {
    /// Never reviewed.
    case new = 0
    /// In the initial learning steps before the first interval is computed.
    case learning = 1
    /// In normal long-interval review.
    case review = 2
    /// Previously in `.review` but lapsed and is being recovered.
    case relearning = 3
}
