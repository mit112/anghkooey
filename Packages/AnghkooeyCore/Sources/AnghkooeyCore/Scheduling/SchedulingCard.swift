import Foundation

/// In-memory snapshot of a card's scheduling state, decoupled from the
/// persistence-layer `Card` model.
///
/// The engine consumes and returns `SchedulingCard` values; mapping to and
/// from the SwiftData `Card` model happens at the persistence boundary so the
/// scheduler stays a pure function and the parity harness can drive it
/// without standing up a `ModelContainer`.
///
/// Field set mirrors `ts-fsrs v5.4.0` (`packages/fsrs/src/models.ts`'s
/// `CardInput`) translated to Swift naming conventions. Snake-case names
/// from the JS reference MUST NOT appear here — the M1 forbidden-pattern
/// script enforces that.
public struct SchedulingCard: Equatable, Sendable {
    /// Lifecycle state. Maps 1:1 to `CardState.rawValue` used in persistence.
    public var state: CardState

    /// FSRS stability (the "S" term) — memory durability in days.
    public var stability: Double

    /// FSRS difficulty (the "D" term) — bounded `[1, 10]` after the first review.
    public var difficulty: Double

    /// Wall-clock instant this card becomes due for review.
    public var due: Date

    /// Total number of review attempts (any rating).
    public var reps: Int

    /// Number of times this card has lapsed from `.review` into `.relearning`.
    public var lapses: Int

    /// Position within `FSRSParameters.learningStepsSeconds` (when state is
    /// `.learning`) or `relearningStepsSeconds` (when `.relearning`). Zero
    /// when the card has not yet entered a step machine.
    public var learningSteps: Int

    /// Integer-day interval from the last review to `due`. Stored as `Double`
    /// because `ts-fsrs` exposes it that way for fractional intervals; the
    /// parity harness compares the integer-day projection.
    public var scheduledDays: Double

    /// Days between the previous review and the one that produced this state.
    /// Zero on first review.
    public var elapsedDays: Double

    /// Instant of the most recent review. `nil` until the card has been rated
    /// at least once.
    public var lastReview: Date?

    /// Designated initializer.
    public init(
        state: CardState,
        stability: Double,
        difficulty: Double,
        due: Date,
        reps: Int,
        lapses: Int,
        learningSteps: Int,
        scheduledDays: Double,
        elapsedDays: Double,
        lastReview: Date?
    ) {
        self.state = state
        self.stability = stability
        self.difficulty = difficulty
        self.due = due
        self.reps = reps
        self.lapses = lapses
        self.learningSteps = learningSteps
        self.scheduledDays = scheduledDays
        self.elapsedDays = elapsedDays
        self.lastReview = lastReview
    }

    /// Construct a freshly-created card that has never been reviewed.
    /// Matches `ts-fsrs.createEmptyCard(now)`.
    public static func newCard(due: Date) -> SchedulingCard {
        SchedulingCard(
            state: .new,
            stability: 0,
            difficulty: 0,
            due: due,
            reps: 0,
            lapses: 0,
            learningSteps: 0,
            scheduledDays: 0,
            elapsedDays: 0,
            lastReview: nil
        )
    }
}
