import Foundation

/// One review in a card's replayed history, decoupled from `ReviewLog`.
///
/// Carries ONLY the inputs the optimizer needs. It deliberately does NOT carry
/// `stabilityBefore`/`difficultyBefore`: those were computed under the default
/// `w` and are wrong for any candidate `w`. State is replayed inside the loss.
public struct ReviewSample: Equatable, Sendable {
    /// UTC calendar-day diff from the prior review (0 on the first review and
    /// on same-day reviews). Matches `ReviewLog.elapsedDays`.
    public let elapsedDays: Double
    /// The grade the user gave.
    public let rating: Rating
    /// True when this review fell on the same UTC day as the prior one
    /// (`elapsedDays == 0` for a non-first review). Same-day reviews update
    /// state but never contribute to the loss (py-fsrs semantics).
    public let sameDay: Bool

    public init(elapsedDays: Double, rating: Rating, sameDay: Bool) {
        self.elapsedDays = elapsedDays
        self.rating = rating
        self.sameDay = sameDay
    }
}
