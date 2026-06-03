import Foundation
import OSLog

/// Fits a personal FSRS-6 weight set to a user's review history.
///
/// **One math surface.** Predicted recall and memory-state evolution come
/// exclusively from `LiveFSRS6Engine` primitives (`forgettingCurve`,
/// `nextMemoryState`). The optimizer never re-derives the FSRS formulas — it
/// replays each card's history under a *candidate* parameter set and scores the
/// predicted recall against the actual outcome with binary cross-entropy.
///
/// **Why finite differences.** The loss uses *actual* `elapsedDays`, not
/// scheduled intervals, so the forward model is a smooth function of `w` with
/// no integer-rounding discontinuity in the gradient path. Central finite
/// differences over the parity-verified engine are therefore sound and avoid a
/// second, hand-derived analytic-gradient math surface that could drift from the
/// scheduler. See ADR-0005 (T8) for the correctness-over-speed rationale and the
/// analytic-gradient escalation trigger.
///
/// The Python parity oracle (`scripts/fsrs-optimizer/`) runs this *same*
/// FD-Adam algorithm in stdlib Python, so the fixture is a direct algorithmic
/// parity target, not an autograd reference.
public struct LiveFSRSOptimizer: FSRSOptimizer {
    public struct Config: Sendable {
        /// Mini-batch Adam epochs over the full card set. Calibrated against the
        /// T2 parity fixture (60 matches the Python oracle).
        public var epochs: Int = 60
        /// Cards sampled per epoch (without replacement). Batches smaller than
        /// the card count introduce stochastic-gradient noise.
        public var batchSize: Int = 256
        public var learningRate: Double = 0.01
        public var seed: UInt64 = 42
        /// 1-D Adam iterations for each `w[0..3]` initial-stability bucket.
        public var pretrainIterations: Int = 200
        public var pretrainLearningRate: Double = 0.05
        public init() {}
    }

    public let config: Config

    public init(config: Config = Config()) {
        self.config = config
    }

    // MARK: Adam constants

    private static let beta1 = 0.9
    private static let beta2 = 0.999
    private static let adamEpsilon = 1e-8

    /// BCE probability clip — keeps `log` finite at the recall extremes.
    private static let recallClipLow = 1e-7
    private static let recallClipHigh = 1.0 - 1e-7

    /// Per-weight valid ranges (FSRS-6, ts-fsrs v5.4.0). Adam clamps to these
    /// every step. `w8/w13/w14` have no published bound, so they are held in
    /// `[-5, 5]` for numerical stability. Mirrors `W_CLAMPS` in the Python oracle.
    static let weightClamps: [(low: Double, high: Double)] = [
        (0.1, sMax), (0.1, sMax), (0.1, sMax), (0.1, sMax),  // w[0..3]
        (1.0, 10.0), (0.1, 5.0),  (0.1, 5.0),  (0.0, 0.5),   // w[4..7]
        (-5.0, 5.0), (0.1, 3.0),  (0.1, 5.0),  (0.1, 5.0),   // w[8..11]
        (0.1, 5.0),  (-5.0, 5.0), (-5.0, 5.0), (0.1, 1.0),   // w[12..15]
        (1.0, 5.0),  (-2.0, 2.0), (-2.0, 2.0), (0.01, 1.5),  // w[16..19]
        (0.1, 0.8),                                           // w[20]
    ]

    private static let sMax = 36_500.0
    private static let initialStabilityFloor = 0.1

    // MARK: - FSRSOptimizer

    public func optimize(
        _ dataset: OptimizationDataset,
        from initial: FSRSParameters,
        progress: @Sendable (Double) -> Void
    ) async -> OptimizationResult {
        let signposter = CoreLog.poiSignposter
        let signpostID = signposter.makeSignpostID()
        let intervalState = signposter.beginInterval("fsrs-optimization", id: signpostID)
        defer { signposter.endInterval("fsrs-optimization", intervalState) }

        let baselineLoss = meanLoss(dataset, parameters: initial)

        // Phase 1: pretrain initial-stability weights w[0..3].
        var w = initial.w
        pretrainInitialStability(dataset, into: &w)

        // Phase 2: mini-batch Adam over the full 21-weight vector.
        var rng = SeededGenerator(seed: config.seed)
        var m = [Double](repeating: 0, count: 21)
        var v = [Double](repeating: 0, count: 21)
        var step = 0
        let sequences = dataset.cardSequences

        for epoch in 0..<config.epochs {
            let batch = sampleBatch(sequences, size: config.batchSize, using: &rng)
            let batchDataset = OptimizationDataset(cardSequences: batch)
            let grads = gradient(batchDataset, parameters: initial.withWeights(w))
            step += 1
            let bias1 = 1 - Foundation.pow(Self.beta1, Double(step))
            let bias2 = 1 - Foundation.pow(Self.beta2, Double(step))
            for i in 0..<21 {
                m[i] = Self.beta1 * m[i] + (1 - Self.beta1) * grads[i]
                v[i] = Self.beta2 * v[i] + (1 - Self.beta2) * grads[i] * grads[i]
                let mHat = m[i] / bias1
                let vHat = v[i] / bias2
                w[i] -= config.learningRate * mHat / (Foundation.sqrt(vHat) + Self.adamEpsilon)
                let bounds = Self.weightClamps[i]
                w[i] = min(max(w[i], bounds.low), bounds.high)
            }
            progress(Double(epoch + 1) / Double(config.epochs))
        }

        let optimizedParameters = initial.withWeights(w)
        let optimizedLoss = meanLoss(dataset, parameters: optimizedParameters)
        let weightDeltas = zip(w, initial.w).map { $0 - $1 }
        let achievedRetention = meanPredictedRecall(dataset, parameters: optimizedParameters)

        return OptimizationResult(
            baselineLoss: baselineLoss,
            optimizedLoss: optimizedLoss,
            optimizedParameters: optimizedParameters,
            weightDeltas: weightDeltas,
            achievedRetention: achievedRetention
        )
    }

    // MARK: - Loss / gradient (internal — tested directly)

    /// Mean binary-cross-entropy over eligible samples under `parameters`.
    /// Replays state through `LiveFSRS6Engine`; same surface as the scheduler.
    func meanLoss(_ dataset: OptimizationDataset, parameters: FSRSParameters) -> Double {
        let engine = LiveFSRS6Engine(parameters: parameters)
        var total = 0.0
        var count = 0
        forEachEligible(dataset, engine: engine) { r, y in
            total += -(y * Foundation.log(r) + (1 - y) * Foundation.log(1 - r))
            count += 1
        }
        return count > 0 ? total / Double(count) : 0
    }

    /// Central finite-difference gradient of `meanLoss` w.r.t. each weight.
    /// Per-parameter relative epsilon `eps_i = max(1e-5, 1e-4·|w_i|)` because the
    /// 21 weights span ~`0.001`–`8.3`; a fixed absolute step would be wrong at
    /// both ends. Calibrated against the T2 fixture (see ADR-0005).
    func gradient(_ dataset: OptimizationDataset, parameters: FSRSParameters) -> [Double] {
        let w = parameters.w
        var grads = [Double](repeating: 0, count: 21)
        for i in 0..<21 {
            let eps = max(1e-5, 1e-4 * abs(w[i]))
            var wPlus = w; wPlus[i] += eps
            var wMinus = w; wMinus[i] -= eps
            let lossPlus = meanLoss(dataset, parameters: parameters.withWeights(wPlus))
            let lossMinus = meanLoss(dataset, parameters: parameters.withWeights(wMinus))
            grads[i] = (lossPlus - lossMinus) / (2 * eps)
        }
        return grads
    }

    /// Pretrains the four initial-stability weights `w[0..3]` (one per
    /// first-review rating bucket) before the full 21-weight phase.
    ///
    /// Replicates the recorded py-fsrs procedure (see the fixture generator's
    /// header): group cards by their *first* review rating, collect each card's
    /// `(secondReviewElapsed, passed?)` transition, and fit a single initial
    /// stability per bucket via 1-D Adam minimising the same BCE. The forgetting
    /// curve uses the starting parameters' decay (`w[20]`), which the main phase
    /// has not yet touched.
    func pretrainInitialStability(_ dataset: OptimizationDataset, into w: inout [Double]) {
        let engine = LiveFSRS6Engine(parameters: FSRSParameters.default.withWeights(w))
        var buckets: [Rating: [(elapsed: Double, outcome: Double)]] = [
            .again: [], .hard: [], .good: [], .easy: [],
        ]
        for seq in dataset.cardSequences {
            guard seq.count >= 2 else { continue }
            let secondReview = seq[1]
            if secondReview.sameDay { continue }
            let outcome = (secondReview.rating == .again) ? 0.0 : 1.0
            buckets[seq[0].rating, default: []].append((secondReview.elapsedDays, outcome))
        }

        for rating in [Rating.again, .hard, .good, .easy] {
            guard let pairs = buckets[rating], !pairs.isEmpty else { continue }

            func bucketLoss(_ stability: Double) -> Double {
                let s = max(stability, 0.001)
                var total = 0.0
                for pair in pairs {
                    let raw = engine.forgettingCurve(elapsedDays: pair.elapsed, stability: s)
                    let r = min(max(raw, Self.recallClipLow), Self.recallClipHigh)
                    total += -(pair.outcome * Foundation.log(r) + (1 - pair.outcome) * Foundation.log(1 - r))
                }
                return total / Double(pairs.count)
            }

            var s = 1.0
            var m = 0.0, v = 0.0, step = 0
            for _ in 0..<config.pretrainIterations {
                let eps = max(1e-5, 1e-4 * abs(s))
                let grad = (bucketLoss(s + eps) - bucketLoss(s - eps)) / (2 * eps)
                step += 1
                m = Self.beta1 * m + (1 - Self.beta1) * grad
                v = Self.beta2 * v + (1 - Self.beta2) * grad * grad
                let mHat = m / (1 - Foundation.pow(Self.beta1, Double(step)))
                let vHat = v / (1 - Foundation.pow(Self.beta2, Double(step)))
                s -= config.pretrainLearningRate * mHat / (Foundation.sqrt(vHat) + Self.adamEpsilon)
                s = min(max(s, Self.initialStabilityFloor), Self.sMax)
            }
            w[rating.rawValue - 1] = s
        }
    }

    // MARK: - Private replay

    /// Mean predicted recall over eligible samples (the model's achieved
    /// retention on the user's own history). Surfaced as `achievedRetention`.
    private func meanPredictedRecall(_ dataset: OptimizationDataset, parameters: FSRSParameters) -> Double {
        let engine = LiveFSRS6Engine(parameters: parameters)
        var sum = 0.0
        var count = 0
        forEachEligible(dataset, engine: engine) { r, _ in
            sum += r
            count += 1
        }
        return count > 0 ? sum / Double(count) : 0
    }

    /// The single replay loop. For each eligible sample (`index > 0`,
    /// `!sameDay`, `stability > 0`) it computes the clipped predicted recall and
    /// the pass/fail label and hands them to `body`. State advances for *every*
    /// sample (including the first and same-day reviews) via `nextMemoryState`.
    private func forEachEligible(
        _ dataset: OptimizationDataset,
        engine: LiveFSRS6Engine,
        _ body: (_ recall: Double, _ label: Double) -> Void
    ) {
        for seq in dataset.cardSequences {
            var d = 0.0
            var s = 0.0
            for (index, sample) in seq.enumerated() {
                if index > 0 && !sample.sameDay && s > 0 {
                    let raw = engine.forgettingCurve(elapsedDays: sample.elapsedDays, stability: s)
                    let r = min(max(raw, Self.recallClipLow), Self.recallClipHigh)
                    let y = (sample.rating == .again) ? 0.0 : 1.0
                    body(r, y)
                }
                let next = engine.nextMemoryState(
                    d: d, s: s, t: Int(sample.elapsedDays), g: sample.rating)
                d = next.d
                s = next.s
            }
        }
    }

    /// Samples `size` card sequences without replacement using `rng`. Returns the
    /// full set when `size >= count`.
    private func sampleBatch(
        _ sequences: [[ReviewSample]],
        size: Int,
        using rng: inout SeededGenerator
    ) -> [[ReviewSample]] {
        guard size < sequences.count else { return sequences }
        var shuffled = sequences
        shuffled.shuffle(using: &rng)
        return Array(shuffled.prefix(size))
    }
}
