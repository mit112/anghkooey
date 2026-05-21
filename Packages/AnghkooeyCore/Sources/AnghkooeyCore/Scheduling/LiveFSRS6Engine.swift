import Foundation

/// Production FSRS-6 implementation.
///
/// Ports the algorithm and short-term scheduler from `ts-fsrs v5.4.0` at the
/// commit pinned by ADR-0002. The implementation is a deliberate line-by-line
/// translation — paraphrasing the math invites a sign flip the parity harness
/// then chases for hours. When in doubt, the JS source is the oracle.
///
/// State machines:
/// - `.new` / `.learning` / `.relearning` → handled via the short-term
///   step strategy (`BasicLearningStepsStrategy`).
/// - `.review` → recall/forget stability with retrievability from the
///   forgetting curve; intervals derived from `next_interval` with the
///   `hard ≤ good < easy` monotonicity constraint from `BasicScheduler`.
///
/// The long-term scheduler (`enableShortTerm == false`) is intentionally
/// not specialised: callers passing that flag get the same basic dispatch,
/// with learning steps absent from the strategy. The default FSRS-6 parameter
/// set (ADR-0002) is short-term-enabled, so this is fine for parity. A
/// dedicated long-term path can land later without changing the public API.
public struct LiveFSRS6Engine: FSRS6Engine {
    public let parameters: FSRSParameters

    // MARK: Cached derived constants

    /// `decay = -w[20]`. Negative — that is intentional and matches `ts-fsrs`.
    @usableFromInline internal let decay: Double

    /// `factor = exp(ln(0.9) / decay) - 1`, rounded to 8 decimals.
    @usableFromInline internal let factor: Double

    /// `intervalModifier = (requestRetention^(1/decay) - 1) / factor`,
    /// rounded to 8 decimals. Multiply stability by this to get the
    /// integer-day interval at the requested retention.
    @usableFromInline internal let intervalModifier: Double

    // MARK: Constants

    @usableFromInline internal static let sMin: Double = 0.001
    @usableFromInline internal static let sMax: Double = 36_500.0

    /// Construct an engine with the given parameter set. Defaults to
    /// `FSRSParameters.default` (the ADR-0002-pinned 21-weight vector).
    public init(parameters: FSRSParameters = .default) {
        self.parameters = parameters
        let d = -parameters.w[20]
        let f = Self.roundTo(Foundation.exp(Foundation.log(0.9) / d) - 1.0, decimals: 8)
        self.decay = d
        self.factor = f
        self.intervalModifier = Self.roundTo(
            (Foundation.pow(parameters.requestRetention, 1.0 / d) - 1.0) / f,
            decimals: 8
        )
    }

    // MARK: - next

    public func next(card: SchedulingCard, rating: Rating, now: Date) throws -> SchedulerOutput {
        guard parameters.w.count == 21 else {
            throw SchedulingError.unsupportedParameterLength(parameters.w.count)
        }
        if let last = card.lastReview, now < last {
            throw SchedulingError.reviewedBeforeLastReview
        }
        if card.state == .new
            && (card.stability != 0 || card.difficulty != 0 || card.lastReview != nil) {
            throw SchedulingError.invalidNewCardSnapshot
        }

        // ts-fsrs AbstractScheduler.init():
        // - elapsed = 0 for State.New, else integer UTC calendar-day diff
        //   between the prior review and now.
        // - card's prior-review pointer becomes `now`; reps += 1.
        let elapsed: Int
        if card.state != .new, let last = card.lastReview {
            elapsed = Self.dateDiffInUTCDays(from: last, to: now)
        } else {
            elapsed = 0
        }

        // Pre-review log — mirrors `AbstractScheduler.buildLog` but typed
        // to our `ReviewLogEntry` shape (pre-review snapshot of the card).
        let log = ReviewLogEntry(
            rating: rating,
            stateBefore: card.state,
            stabilityBefore: card.stability,
            difficultyBefore: card.difficulty,
            elapsedDays: Double(elapsed),
            scheduledDays: card.scheduledDays,
            reviewedAt: now
        )

        // Start from the post-init mutation: `reps += 1`, `lastReview = now`,
        // `elapsedDays = elapsed`. State-specific dispatch then mutates this.
        var next = card
        next.reps += 1
        next.lastReview = now
        next.elapsedDays = Double(elapsed)

        switch card.state {
        case .new:
            // BasicScheduler.newState
            let ds = nextMemoryState(d: card.difficulty, s: card.stability, t: elapsed, g: rating)
            next.difficulty = ds.d
            next.stability = ds.s
            applyLearningSteps(
                next: &next,
                grade: rating,
                toState: .learning,
                currentStateForStrategy: card.state,
                currentLearningSteps: card.learningSteps,
                elapsed: elapsed,
                reviewTime: now
            )

        case .learning, .relearning:
            // BasicScheduler.learningState
            let ds = nextMemoryState(d: card.difficulty, s: card.stability, t: elapsed, g: rating)
            next.difficulty = ds.d
            next.stability = ds.s
            applyLearningSteps(
                next: &next,
                grade: rating,
                toState: card.state, // stays in Learning or Relearning
                currentStateForStrategy: card.state,
                currentLearningSteps: card.learningSteps,
                elapsed: elapsed,
                reviewTime: now
            )

        case .review:
            // BasicScheduler.reviewState
            let r = forgettingCurve(elapsedDays: Double(elapsed), stability: card.stability)
            let ds = nextMemoryState(
                d: card.difficulty,
                s: card.stability,
                t: elapsed,
                g: rating,
                retrievability: r
            )
            next.difficulty = ds.d
            next.stability = ds.s

            if rating == .again {
                // The Again path runs through the relearning step machine.
                // After this, `lapses += 1` (per BasicScheduler.reviewState).
                applyLearningSteps(
                    next: &next,
                    grade: .again,
                    toState: .relearning,
                    currentStateForStrategy: card.state, // .review
                    currentLearningSteps: card.learningSteps,
                    elapsed: elapsed,
                    reviewTime: now
                )
                next.lapses += 1
            } else {
                // hard / good / easy: compute the full triple and pick.
                // The monotonicity constraint hard ≤ good < easy is applied
                // exactly as in `BasicScheduler.next_interval` (private).
                let hardS = computeRecallStability(d: card.difficulty, s: card.stability, r: r, g: .hard)
                let goodS = computeRecallStability(d: card.difficulty, s: card.stability, r: r, g: .good)
                let easyS = computeRecallStability(d: card.difficulty, s: card.stability, r: r, g: .easy)

                var hardI = nextInterval(stability: hardS)
                var goodI = nextInterval(stability: goodS)
                hardI = min(hardI, goodI)
                goodI = max(goodI, hardI + 1)
                let easyI = max(nextInterval(stability: easyS), goodI + 1)

                let chosen: Int
                switch rating {
                case .hard: chosen = hardI
                case .good: chosen = goodI
                case .easy: chosen = easyI
                case .again: chosen = goodI // unreachable
                }

                next.state = .review
                next.learningSteps = 0
                next.scheduledDays = Double(chosen)
                next.due = now.addingTimeInterval(Double(chosen) * 86_400)
            }
        }

        return SchedulerOutput(card: next, log: log)
    }

    // MARK: - Learning steps strategy (BasicLearningStepsStrategy + applyLearningSteps)

    /// Mirrors `BasicScheduler.applyLearningSteps` + `BasicLearningStepsStrategy`.
    ///
    /// `currentStateForStrategy` is the card's pre-review `.state`; it picks
    /// which step list (learning vs relearning) the strategy reads. `toState`
    /// is the candidate post-review state if the scheduled interval falls
    /// inside the step machine; if it doesn't, the card graduates to
    /// `.review` regardless.
    private func applyLearningSteps(
        next: inout SchedulingCard,
        grade: Rating,
        toState: CardState,
        currentStateForStrategy: CardState,
        currentLearningSteps: Int,
        elapsed: Int,
        reviewTime: Date
    ) {
        let info = learningInfo(
            state: currentStateForStrategy,
            currentStep: currentLearningSteps,
            grade: grade
        )

        let scheduledMinutes = max(0, info.scheduledMinutes)
        let nextSteps = max(0, info.nextStep)

        if scheduledMinutes > 0 && scheduledMinutes < 1440 {
            next.learningSteps = nextSteps
            next.scheduledDays = 0
            next.state = toState
            let rounded = scheduledMinutes.rounded()
            next.due = reviewTime.addingTimeInterval(rounded * 60.0)
        } else {
            next.state = .review
            if scheduledMinutes >= 1440 {
                next.learningSteps = nextSteps
                let rounded = scheduledMinutes.rounded()
                next.due = reviewTime.addingTimeInterval(rounded * 60.0)
                next.scheduledDays = (rounded / 1440.0).rounded(.down)
            } else {
                next.learningSteps = 0
                let interval = nextInterval(stability: next.stability)
                next.scheduledDays = Double(interval)
                next.due = reviewTime.addingTimeInterval(Double(interval) * 86_400.0)
            }
        }
        _ = elapsed // currently unused here — fuzz path consumes it.
    }

    /// Mirrors `BasicLearningStepsStrategy` for one grade.
    private struct LearningInfo {
        let scheduledMinutes: Double
        let nextStep: Int
    }

    private func learningInfo(state: CardState, currentStep: Int, grade: Rating) -> LearningInfo {
        let steps: [TimeInterval] =
            (state == .relearning || state == .review)
                ? parameters.relearningStepsSeconds
                : parameters.learningStepsSeconds
        let stepsLength = steps.count
        let curStep = max(0, currentStep)

        if stepsLength == 0 || curStep >= stepsLength {
            return LearningInfo(scheduledMinutes: 0, nextStep: 0)
        }

        let firstStepMin = steps[0] / 60.0

        if state == .review {
            // Review → Again only; scheduled is the current step's duration.
            let stepInfo = steps[curStep] / 60.0
            if grade == .again {
                return LearningInfo(scheduledMinutes: stepInfo, nextStep: 0)
            }
            return LearningInfo(scheduledMinutes: 0, nextStep: 0)
        }

        // .new / .learning / .relearning
        switch grade {
        case .again:
            return LearningInfo(scheduledMinutes: firstStepMin, nextStep: 0)
        case .hard:
            let hardMin: Double
            if stepsLength == 1 {
                hardMin = (firstStepMin * 1.5).rounded()
            } else {
                let nextStepMin = steps[1] / 60.0
                hardMin = ((firstStepMin + nextStepMin) / 2.0).rounded()
            }
            return LearningInfo(scheduledMinutes: hardMin, nextStep: curStep)
        case .good:
            let nextIdx = curStep + 1
            guard nextIdx < stepsLength else {
                return LearningInfo(scheduledMinutes: 0, nextStep: 0)
            }
            let nextMin = (steps[nextIdx] / 60.0).rounded()
            return LearningInfo(scheduledMinutes: nextMin, nextStep: nextIdx)
        case .easy:
            // Strategy returns nothing for Easy in learning states.
            return LearningInfo(scheduledMinutes: 0, nextStep: 0)
        }
    }

    // MARK: - Memory state (algorithm.next_state)

    @usableFromInline
    internal func nextMemoryState(
        d: Double,
        s: Double,
        t: Int,
        g: Rating,
        retrievability: Double? = nil
    ) -> (d: Double, s: Double) {
        // Seed path — first review of a brand-new card.
        if d == 0 && s == 0 {
            let initD = Self.clamp(initDifficulty(g), low: 1.0, high: 10.0)
            return (initD, initStability(g))
        }

        let r = retrievability ?? forgettingCurve(elapsedDays: Double(t), stability: s)
        let w = parameters.w
        let newS: Double

        if t == 0 && parameters.enableShortTerm {
            newS = nextShortTermStability(s: s, g: g)
        } else if g == .again {
            let sAfterFail = nextForgetStability(d: d, s: s, r: r)
            let (w17, w18): (Double, Double) =
                parameters.enableShortTerm ? (w[17], w[18]) : (0, 0)
            let nextSMin = s / Foundation.exp(w17 * w18)
            newS = Self.clamp(Self.roundTo(nextSMin, decimals: 8), low: Self.sMin, high: sAfterFail)
        } else {
            newS = nextRecallStability(d: d, s: s, r: r, g: g)
        }

        let newD = nextDifficulty(d: d, g: g)
        return (newD, newS)
    }

    // MARK: - Math primitives (internal for testability)

    @usableFromInline
    internal func forgettingCurve(elapsedDays: Double, stability: Double) -> Double {
        Self.roundTo(
            Foundation.pow(1.0 + factor * elapsedDays / stability, decay),
            decimals: 8
        )
    }

    @usableFromInline
    internal func initStability(_ g: Rating) -> Double {
        max(parameters.w[g.rawValue - 1], 0.1)
    }

    @usableFromInline
    internal func initDifficulty(_ g: Rating) -> Double {
        let w = parameters.w
        let d = w[4] - Foundation.exp(Double(g.rawValue - 1) * w[5]) + 1.0
        return Self.roundTo(d, decimals: 8)
    }

    @usableFromInline
    internal func linearDamping(deltaD: Double, oldD: Double) -> Double {
        Self.roundTo(deltaD * (10.0 - oldD) / 9.0, decimals: 8)
    }

    @usableFromInline
    internal func meanReversion(initial: Double, current: Double) -> Double {
        let w7 = parameters.w[7]
        return Self.roundTo(w7 * initial + (1.0 - w7) * current, decimals: 8)
    }

    @usableFromInline
    internal func nextDifficulty(d: Double, g: Rating) -> Double {
        let w = parameters.w
        let deltaD = -w[6] * Double(g.rawValue - 3)
        let nextD = d + linearDamping(deltaD: deltaD, oldD: d)
        // `init_difficulty(Easy)` is intentionally NOT clamped here — the
        // unclamped raw value is the input to mean_reversion. Only the final
        // result is clamped to [1, 10].
        return Self.clamp(meanReversion(initial: initDifficulty(.easy), current: nextD), low: 1.0, high: 10.0)
    }

    @usableFromInline
    internal func nextRecallStability(d: Double, s: Double, r: Double, g: Rating) -> Double {
        let w = parameters.w
        let hardPenalty: Double = (g == .hard) ? w[15] : 1.0
        let easyBound: Double = (g == .easy) ? w[16] : 1.0
        let value = s * (1.0
            + Foundation.exp(w[8])
                * (11.0 - d)
                * Foundation.pow(s, -w[9])
                * (Foundation.exp((1.0 - r) * w[10]) - 1.0)
                * hardPenalty
                * easyBound)
        return Self.roundTo(Self.clamp(value, low: Self.sMin, high: Self.sMax), decimals: 8)
    }

    @usableFromInline
    internal func nextForgetStability(d: Double, s: Double, r: Double) -> Double {
        let w = parameters.w
        let value = w[11]
            * Foundation.pow(d, -w[12])
            * (Foundation.pow(s + 1.0, w[13]) - 1.0)
            * Foundation.exp((1.0 - r) * w[14])
        return Self.roundTo(Self.clamp(value, low: Self.sMin, high: Self.sMax), decimals: 8)
    }

    @usableFromInline
    internal func nextShortTermStability(s: Double, g: Rating) -> Double {
        let w = parameters.w
        let sinc = Foundation.pow(s, -w[19])
            * Foundation.exp(w[17] * (Double(g.rawValue - 3) + w[18]))
        let masked = (g.rawValue >= Rating.hard.rawValue) ? max(sinc, 1.0) : sinc
        return Self.roundTo(Self.clamp(s * masked, low: Self.sMin, high: Self.sMax), decimals: 8)
    }

    @usableFromInline
    internal func nextInterval(stability: Double) -> Int {
        let raw = (stability * intervalModifier).rounded()
        let clamped = max(1.0, min(raw, Double(parameters.maximumInterval)))
        return Int(clamped)
    }

    /// Convenience used by the review-state triple.
    private func computeRecallStability(d: Double, s: Double, r: Double, g: Rating) -> Double {
        nextRecallStability(d: d, s: s, r: r, g: g)
    }

    // MARK: - Helpers

    @usableFromInline
    internal static func roundTo(_ x: Double, decimals: Int) -> Double {
        let m = Foundation.pow(10.0, Double(decimals))
        return (x * m).rounded() / m
    }

    @usableFromInline
    internal static func clamp(_ x: Double, low: Double, high: Double) -> Double {
        min(max(x, low), high)
    }

    /// UTC calendar-day difference. Mirrors `ts-fsrs`'s `dateDiffInDays`,
    /// which floors `(Date.UTC(later) - Date.UTC(earlier)) / 86_400_000`.
    @usableFromInline
    internal static func dateDiffInUTCDays(from earlier: Date, to later: Date) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let e = cal.dateComponents([.year, .month, .day], from: earlier)
        let l = cal.dateComponents([.year, .month, .day], from: later)
        guard let ed = cal.date(from: e), let ld = cal.date(from: l) else { return 0 }
        return Int(Foundation.floor(ld.timeIntervalSince(ed) / 86_400.0))
    }
}
