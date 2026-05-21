import Foundation

/// Contract for the FSRS-6 scheduler.
///
/// The protocol is intentionally narrow: a single pure function from
/// `(SchedulingCard, Rating, Date)` to `SchedulerOutput`. All state lives in
/// the input — the engine has no internal mutable state — which is what lets
/// the parity harness drive identical inputs through both the Swift port and
/// the pinned `ts-fsrs` reference.
///
/// `parameters` is exposed so callers (and the parity fixture loader) can
/// pin or override the 21-weight default. Two production-shaped conformers
/// ship in this module:
///
/// - ``LiveFSRS6Engine`` — the real port. `next(...)` traps until the math is
///   landed in M1 T4.
/// - ``MockFSRS6Engine`` — deterministic placeholder used by downstream
///   packages that need *something* to call while T4 is in flight, and by
///   tests that don't care about the math.
public protocol FSRS6Engine: Sendable {
    /// Parameter set this engine instance was constructed with.
    var parameters: FSRSParameters { get }

    /// Apply `rating` to `card` at instant `now`, returning the post-review
    /// card state and a log entry capturing the pre-review snapshot.
    ///
    /// - Parameters:
    ///   - card: Card state prior to this review.
    ///   - rating: User's review grade.
    ///   - now: Wall-clock instant the review occurred. The engine recomputes
    ///     `elapsedDays` from `(now - card.lastReview)`; callers must not
    ///     pre-fill it.
    /// - Returns: Updated card + log entry, intended to be written
    ///   atomically by the persistence layer.
    /// - Throws: `SchedulingError` for malformed inputs (e.g.
    ///   `now < card.lastReview`).
    func next(card: SchedulingCard, rating: Rating, now: Date) throws -> SchedulerOutput
}

/// Errors raised by an `FSRS6Engine` for invalid inputs.
public enum SchedulingError: Error, Equatable, Sendable {
    /// `now` was strictly less than `card.lastReview`. Clock skew, not a
    /// scheduling decision.
    case reviewedBeforeLastReview
    /// `card.state == .new` but a non-zero `stability` / `difficulty` /
    /// `lastReview` was supplied. Engine refuses to second-guess.
    case invalidNewCardSnapshot
    /// `parameters.w.count != 21`. Older-version weight vectors (length 17
    /// or 19) are not supported.
    case unsupportedParameterLength(Int)
}

// `LiveFSRS6Engine` is defined in `LiveFSRS6Engine.swift`.
