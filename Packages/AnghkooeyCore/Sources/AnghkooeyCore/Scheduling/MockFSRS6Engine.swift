import Foundation

/// Deterministic placeholder ``FSRS6Engine`` for use by downstream packages
/// while the real port (M1 T4) is in flight, and by tests that need a
/// scheduler-shaped collaborator but don't care about FSRS-6 fidelity.
///
/// **This is not FSRS-6.** The transitions below are chosen for determinism
/// and minimal surprise, not correctness. Any test that asserts real
/// scheduling behaviour MUST use ``LiveFSRS6Engine`` (once T4 lands) or the
/// parity-fixture harness directly.
///
/// ## Contract that the implementation MUST satisfy
///
/// `next(card:rating:now:)` is the only behavioural surface and must produce
/// the following deterministic mapping. The values are pinned by
/// `MockFSRS6EngineContractTests`; do not change them without updating both.
///
/// Common to every rating:
/// - `output.card.reps == card.reps + 1`
/// - `output.card.lastReview == now`
/// - `output.card.elapsedDays ==` days between `card.lastReview` and `now`
///   (or `0` when `card.lastReview == nil`)
/// - `output.log.rating == rating`
/// - `output.log.stateBefore == card.state`
/// - `output.log.stabilityBefore == card.stability`
/// - `output.log.difficultyBefore == card.difficulty`
/// - `output.log.elapsedDays == output.card.elapsedDays`
/// - `output.log.scheduledDays == card.scheduledDays`
/// - `output.log.reviewedAt == now`
///
/// Rating-specific transitions:
/// - `.again` → `state = .relearning`, `lapses += 1`,
///   `due = now + 600s`, `scheduledDays = 0`
/// - `.hard`  → `state = .review`,     `lapses` unchanged,
///   `due = now + 600s`, `scheduledDays = 0`
/// - `.good`  → `state = .review`,     `lapses` unchanged,
///   `due = now + 86_400s`, `scheduledDays = 1`
/// - `.easy`  → `state = .review`,     `lapses` unchanged,
///   `due = now + 4 * 86_400s`, `scheduledDays = 4`
///
/// Stability and difficulty are passed through unchanged — the mock has no
/// concept of memory dynamics.
///
/// Validation: if `now < card.lastReview ?? .distantPast`, throw
/// `SchedulingError.reviewedBeforeLastReview`.
public struct MockFSRS6Engine: FSRS6Engine {
    public let parameters: FSRSParameters

    /// Construct a mock engine. `parameters` is stored for API symmetry with
    /// ``LiveFSRS6Engine``; the mock does not read any weight values.
    public init(parameters: FSRSParameters = .default) {
        self.parameters = parameters
    }

    public func next(card: SchedulingCard, rating: Rating, now: Date) throws -> SchedulerOutput {
        // Body intentionally unimplemented in the T3 contract — Codex fills
        // this in step 4 of the T3 handoff per the contract documented above.
        // The contract tests in MockFSRS6EngineContractTests are the spec.
        fatalError("MockFSRS6Engine.next is unimplemented — Codex fills per the doc-comment contract in M1 T3")
    }
}
