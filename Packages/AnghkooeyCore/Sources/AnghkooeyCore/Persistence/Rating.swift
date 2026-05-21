import Foundation

/// FSRS-6 four-grade review rating.
///
/// Raw values match the FSRS specification (`Again=1, Hard=2, Good=3, Easy=4`)
/// and are pinned — migrations must preserve them.
public enum Rating: Int, Codable, Sendable, CaseIterable {
    /// Forgot the card; restart the learning sequence.
    case again = 1
    /// Recalled with significant difficulty.
    case hard = 2
    /// Recalled at the expected effort.
    case good = 3
    /// Recalled effortlessly; widen the interval more aggressively.
    case easy = 4
}
