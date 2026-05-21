import Foundation
import Testing
@testable import AnghkooeyCore

// M1 T4 — Unit tests for the FSRS-6 math primitives.
//
// These tests target the individual formulas (forgetting curve, init
// stability/difficulty, mean reversion, recall/forget/short-term stability,
// next interval). A divergence here points directly at which formula is
// wrong; the parity harness (T5) only reports "fixture N step K diverged".
//
// Reference: ts-fsrs v5.4.0 @ 80bab011a7f496b06c99924d54e772cf258244f2
// (`packages/fsrs/src/algorithm.ts`). Expected values below were either
// hand-derived from the published formulas or copied from the first
// few entries of `Tests/AnghkooeyCoreTests/Fixtures/fsrs6-parity.json`.

private let eps = 1e-9

@Suite("FSRS-6 algorithm primitives")
struct FSRSAlgorithmTests {

    private let engine = LiveFSRS6Engine()

    // MARK: - Derived constants

    @Test("decay = -w[20]; factor = exp(ln(0.9)/decay) - 1; rounded to 8")
    func derivedConstants() {
        #expect(abs(engine.decay - (-0.1542)) < eps)
        // factor should put R(t=S) ≈ 0.9 by construction.
        let r = engine.forgettingCurve(elapsedDays: 1.0, stability: 1.0)
        #expect(abs(r - 0.9) < 1e-6)
    }

    @Test("interval modifier scales stability to integer-day interval")
    func intervalModifier() {
        // With requestRetention == 0.9, intervalModifier == 1.0 (modulo
        // 8-decimal rounding) because (0.9^(1/decay)-1) / factor reduces
        // to factor/factor when retention equals the curve target.
        #expect(abs(engine.intervalModifier - 1.0) < 1e-6)
        #expect(engine.nextInterval(stability: 8.2956) == 8)
        #expect(engine.nextInterval(stability: 2.3065) == 2)
        #expect(engine.nextInterval(stability: 0.4) == 1) // clamped to ≥ 1
    }

    @Test("nextInterval clamps to [1, maximumInterval]")
    func nextIntervalClamp() {
        #expect(engine.nextInterval(stability: 0.0) == 1)
        // Stability above the cap → cap.
        let capped = engine.nextInterval(stability: 1_000_000.0)
        #expect(capped == FSRSParameters.default.maximumInterval)
    }

    // MARK: - Forgetting curve

    @Test("R(t=0) = 1 for any positive stability")
    func forgettingCurveAtZero() {
        #expect(engine.forgettingCurve(elapsedDays: 0, stability: 1.0) == 1.0)
        #expect(engine.forgettingCurve(elapsedDays: 0, stability: 50.0) == 1.0)
    }

    @Test("R is monotone decreasing in t for fixed stability")
    func forgettingCurveMonotone() {
        let s = 5.0
        let r0 = engine.forgettingCurve(elapsedDays: 0, stability: s)
        let r1 = engine.forgettingCurve(elapsedDays: 1, stability: s)
        let r2 = engine.forgettingCurve(elapsedDays: 5, stability: s)
        let r3 = engine.forgettingCurve(elapsedDays: 50, stability: s)
        #expect(r0 > r1)
        #expect(r1 > r2)
        #expect(r2 > r3)
        #expect(r3 > 0 && r3 < 1)
    }

    // MARK: - Initial stability / difficulty

    @Test("initStability(rating) = w[rating-1], clamped to ≥ 0.1")
    func initStabilityValues() {
        let w = FSRSParameters.default.w
        #expect(engine.initStability(.again) == max(w[0], 0.1))
        #expect(engine.initStability(.hard) == max(w[1], 0.1))
        #expect(engine.initStability(.good) == max(w[2], 0.1))
        #expect(engine.initStability(.easy) == max(w[3], 0.1))
        // Concrete pinned values (ADR-0002).
        #expect(engine.initStability(.again) == 0.212)
        #expect(engine.initStability(.good) == 2.3065)
        #expect(engine.initStability(.easy) == 8.2956)
    }

    @Test("initDifficulty matches FSRS-6 formula (8-decimal rounded)")
    func initDifficultyValues() {
        // Hand-derived from w[4]=6.4133, w[5]=0.8334:
        //   D0(Again) = 6.4133 - e^0 + 1 = 6.4133
        //   D0(Hard)  = 6.4133 - e^0.8334 + 1 ≈ 5.11217071
        //   D0(Good)  = 6.4133 - e^1.6668 + 1 ≈ 2.11810397
        //   D0(Easy)  = 6.4133 - e^2.5002 + 1 ≈ -4.77163072 (NOT clamped here)
        #expect(abs(engine.initDifficulty(.again) - 6.4133) < eps)
        #expect(abs(engine.initDifficulty(.hard) - 5.11217071) < eps)
        #expect(abs(engine.initDifficulty(.good) - 2.11810397) < eps)
        // Easy is intentionally negative; clamp [1,10] only fires in the
        // seed path of nextMemoryState, not in initDifficulty itself.
        #expect(engine.initDifficulty(.easy) < 0)
    }

    // MARK: - Mean reversion / next difficulty

    @Test("linearDamping: zero delta yields zero, scales by (10-d)/9")
    func linearDampingValues() {
        #expect(engine.linearDamping(deltaD: 0, oldD: 5) == 0)
        // (10-1)/9 = 1.0 → delta_d passes through when oldD=1.
        #expect(engine.linearDamping(deltaD: 1.0, oldD: 1.0) == 1.0)
        // (10-10)/9 = 0 → fully damped when oldD=10.
        #expect(engine.linearDamping(deltaD: 5.0, oldD: 10.0) == 0)
    }

    @Test("meanReversion: w7-weighted average of init and current")
    func meanReversionValues() {
        let w7 = FSRSParameters.default.w[7]
        let r = engine.meanReversion(initial: 1.0, current: 2.0)
        let expected = LiveFSRS6Engine.roundTo(w7 * 1.0 + (1.0 - w7) * 2.0, decimals: 8)
        #expect(r == expected)
    }

    @Test("nextDifficulty matches fixture: Good in Learning at t=0 from 2.11810397")
    func nextDifficultyMatchesFixture() {
        // From fsrs6-parity.json fixture `graduate-good-good`, step 1:
        // D before = 2.11810397, Good → D after = 2.11121424
        let d2 = engine.nextDifficulty(d: 2.11810397, g: .good)
        #expect(abs(d2 - 2.11121424) < eps)
    }

    @Test("nextDifficulty clamps to [1, 10]")
    func nextDifficultyClamps() {
        // Many Easy ratings should drive difficulty toward init_diff(Easy)
        // (large negative) — final value clamped to 1.
        var d = 5.0
        for _ in 0..<20 {
            d = engine.nextDifficulty(d: d, g: .easy)
        }
        #expect(d >= 1.0 && d <= 10.0)
        #expect(d == 1.0)
        // Many Again ratings push toward 10.
        var d2 = 5.0
        for _ in 0..<50 {
            d2 = engine.nextDifficulty(d: d2, g: .again)
        }
        #expect(d2 <= 10.0)
    }

    // MARK: - Stability updates

    @Test("nextShortTermStability(Good) is a no-op at fixture seed values")
    func nextShortTermStabilityGood() {
        // From `graduate-good-good` step 1: Good in Learning at t=0.
        // sinc ends up ≥ 1 for Good via the `max(sinc, 1)` mask, so
        // s * sinc = s.
        let s = engine.nextShortTermStability(s: 2.3065, g: .good)
        #expect(abs(s - 2.3065) < eps)
    }

    @Test("nextShortTermStability(Again) reduces stability (no max-1 mask)")
    func nextShortTermStabilityAgain() {
        // `Again` is below `Hard` raw value, so no mask; sinc < 1 normally.
        let s = engine.nextShortTermStability(s: 2.3065, g: .again)
        #expect(s <= 2.3065)
        #expect(s > 0)
    }

    @Test("nextRecallStability matches fixture: graduate-good-good step 2 stability")
    func nextRecallStabilityMatchesFixture() {
        // After Good in Learning at t=0, then Good at t=2 in Review:
        //   D before step 2 = 2.11121424, S before = 2.3065
        //   R = forgetting_curve(2, 2.3065)
        //   S after = 10.97104786
        let r = engine.forgettingCurve(elapsedDays: 2.0, stability: 2.3065)
        let s = engine.nextRecallStability(d: 2.11121424, s: 2.3065, r: r, g: .good)
        #expect(abs(s - 10.97104786) < eps)
    }

    @Test("nextForgetStability is bounded below by S_MIN")
    func nextForgetStabilityBounded() {
        let s = engine.nextForgetStability(d: 5.0, s: 1.0, r: 0.5)
        #expect(s >= 0.001)
        #expect(s <= 36_500.0)
    }

    @Test("nextMemoryState seed path: new card emits init_S, clamped init_D")
    func seedPathNewCard() {
        // d == 0 && s == 0 → return (clamp(init_diff(g), 1, 10), init_stab(g)).
        let ds = engine.nextMemoryState(d: 0, s: 0, t: 0, g: .easy)
        #expect(ds.s == 8.2956)
        // init_diff(Easy) is negative → clamp to 1.
        #expect(ds.d == 1.0)

        let ds2 = engine.nextMemoryState(d: 0, s: 0, t: 0, g: .good)
        #expect(ds2.s == 2.3065)
        #expect(abs(ds2.d - 2.11810397) < eps)
    }
}

// MARK: - End-to-end: fixture-derived smoke tests of LiveFSRS6Engine.next

@Suite("LiveFSRS6Engine.next — selected fixtures")
struct LiveFSRS6EngineNextTests {

    private let epoch = Date(timeIntervalSince1970: 1_767_225_600) // 2026-01-01T00:00:00Z

    @Test("first-rating-again matches fixture")
    func firstRatingAgain() throws {
        let engine = LiveFSRS6Engine()
        let card = SchedulingCard.newCard(due: epoch)
        let out = try engine.next(card: card, rating: .again, now: epoch)
        #expect(abs(out.card.stability - 0.212) < eps)
        // init_diff(Again) = 6.4133, clamped to [1,10] = 6.4133.
        #expect(abs(out.card.difficulty - 6.4133) < eps)
        #expect(out.card.state == .learning)
        #expect(out.card.scheduledDays == 0)
        #expect(out.card.reps == 1)
        #expect(out.card.lapses == 0)
        #expect(out.card.learningSteps == 0)
        #expect(out.card.due == epoch.addingTimeInterval(60)) // 1m
    }

    @Test("first-rating-good matches fixture")
    func firstRatingGood() throws {
        let engine = LiveFSRS6Engine()
        let card = SchedulingCard.newCard(due: epoch)
        let out = try engine.next(card: card, rating: .good, now: epoch)
        #expect(abs(out.card.stability - 2.3065) < eps)
        #expect(abs(out.card.difficulty - 2.11810397) < eps)
        #expect(out.card.state == .learning)
        #expect(out.card.learningSteps == 1)
        #expect(out.card.due == epoch.addingTimeInterval(600)) // 10m
    }

    @Test("first-rating-easy graduates directly to Review")
    func firstRatingEasy() throws {
        let engine = LiveFSRS6Engine()
        let card = SchedulingCard.newCard(due: epoch)
        let out = try engine.next(card: card, rating: .easy, now: epoch)
        #expect(abs(out.card.stability - 8.2956) < eps)
        // init_diff(Easy) clamped to 1.
        #expect(out.card.difficulty == 1.0)
        #expect(out.card.state == .review)
        #expect(out.card.scheduledDays == 8)
        #expect(out.card.learningSteps == 0)
        #expect(out.card.due == epoch.addingTimeInterval(8 * 86_400))
    }

    @Test("first-rating-hard places card 6 minutes out")
    func firstRatingHard() throws {
        let engine = LiveFSRS6Engine()
        let card = SchedulingCard.newCard(due: epoch)
        let out = try engine.next(card: card, rating: .hard, now: epoch)
        #expect(abs(out.card.stability - 1.2931) < eps)
        #expect(abs(out.card.difficulty - 5.11217071) < eps)
        #expect(out.card.state == .learning)
        // Hard: (firstStep 1m + nextStep 10m) / 2 = 5.5 → rounded to 6 min.
        #expect(out.card.due == epoch.addingTimeInterval(360))
    }

    @Test("graduate-good-good: Good in New, Good at 1m, Good at 2 days")
    func graduateGoodGood() throws {
        let engine = LiveFSRS6Engine()
        var card = SchedulingCard.newCard(due: epoch)

        // Step 0 — Good at t=0
        let step0 = try engine.next(card: card, rating: .good, now: epoch)
        card = step0.card
        #expect(abs(card.stability - 2.3065) < eps)
        #expect(card.state == .learning)
        #expect(card.learningSteps == 1)

        // Step 1 — Good at t = 600s
        let now1 = epoch.addingTimeInterval(600)
        let step1 = try engine.next(card: card, rating: .good, now: now1)
        card = step1.card
        #expect(abs(card.stability - 2.3065) < eps)
        #expect(abs(card.difficulty - 2.11121424) < eps)
        #expect(card.state == .review)
        #expect(card.scheduledDays == 2)
        #expect(card.due == now1.addingTimeInterval(2 * 86_400))

        // Step 2 — Good at t = 173400s (review-state, ~2 days later).
        let now2 = epoch.addingTimeInterval(173_400)
        let step2 = try engine.next(card: card, rating: .good, now: now2)
        card = step2.card
        #expect(abs(card.stability - 10.97104786) < eps)
        #expect(abs(card.difficulty - 2.1043314) < eps)
        #expect(card.state == .review)
    }

    @Test("Again on a graduated card → relearning, +10m, lapses += 1")
    func reviewAgainLapse() throws {
        let engine = LiveFSRS6Engine()
        var card = SchedulingCard.newCard(due: epoch)
        // Easy graduates directly.
        card = try engine.next(card: card, rating: .easy, now: epoch).card
        let now1 = card.due
        let out = try engine.next(card: card, rating: .again, now: now1)
        #expect(out.card.state == .relearning)
        #expect(out.card.lapses == 1)
        #expect(out.card.scheduledDays == 0)
        #expect(out.card.due == now1.addingTimeInterval(600)) // 10m relearning step
    }

    @Test("rejects clock skew with reviewedBeforeLastReview")
    func rejectsClockSkew() throws {
        let engine = LiveFSRS6Engine()
        let card = try engine.next(
            card: SchedulingCard.newCard(due: epoch),
            rating: .good,
            now: epoch
        ).card
        #expect(throws: SchedulingError.reviewedBeforeLastReview) {
            _ = try engine.next(card: card, rating: .good, now: epoch.addingTimeInterval(-60))
        }
    }

    @Test("rejects malformed new-card snapshot")
    func rejectsInvalidNewSnapshot() {
        let engine = LiveFSRS6Engine()
        var card = SchedulingCard.newCard(due: epoch)
        card.stability = 1.0
        #expect(throws: SchedulingError.invalidNewCardSnapshot) {
            _ = try engine.next(card: card, rating: .good, now: epoch)
        }
    }
}
