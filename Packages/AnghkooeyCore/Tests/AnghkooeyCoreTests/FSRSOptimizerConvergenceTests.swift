import Testing
import Foundation
@testable import AnghkooeyCore

@Suite("FSRSOptimizer convergence")
struct FSRSOptimizerConvergenceTests {
    @Test("recovers a known parameter family within tolerance")
    func convergesOnSynthetic() async {
        // 1. Known params: default with a small deterministic perturbation on
        //    the recall-stability weights (w[8..10]).
        var trueW = FSRSParameters.default.w
        trueW[8] += 0.3; trueW[9] += 0.05; trueW[10] += 0.2
        let trueParams = FSRSParameters.default.withWeights(trueW)

        // 2. Generate synthetic eligible-rich sequences under trueParams.
        let dataset = SyntheticReviews.dataset(under: trueParams, cards: 200, seed: 7)
        #expect(dataset.eligibleSampleCount >= 512)

        let opt = LiveFSRSOptimizer()
        let lossUnderTrue = opt.meanLoss(dataset, parameters: trueParams)

        // 3. Optimize from default.
        let result = await opt.optimize(dataset, from: .default, progress: { _ in })

        // 4. Loss recovery within 2% of loss-under-true-params, and beats baseline.
        #expect(result.optimizedLoss <= lossUnderTrue * 1.02)
        #expect(result.optimizedLoss < result.baselineLoss)

        // 5. Calibration: mean predicted recall ≈ mean actual pass-rate ± 0.02.
        let cal = SyntheticReviews.calibration(dataset, parameters: result.optimizedParameters)
        #expect(abs(cal.meanPredicted - cal.meanActual) <= 0.02)
    }
}

/// Test-only synthetic review generator + calibration. Replays state under a
/// known parameter set through `LiveFSRS6Engine` (same math surface the
/// optimizer uses) and samples pass/fail from the true forgetting curve.
enum SyntheticReviews {
    static func dataset(under params: FSRSParameters, cards: Int, seed: UInt64) -> OptimizationDataset {
        var rng = SeededGenerator(seed: seed)
        let engine = LiveFSRS6Engine(parameters: params)
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        var rows: [OptimizationReviewLogRow] = []
        let firstRatings: [Rating] = [.again, .hard, .good, .good, .good, .easy]
        let passRatings: [Rating] = [.hard, .good, .good, .easy]

        for cardIdx in 0..<cards {
            let cardID = UUID()
            var d = 0.0, s = 0.0
            var elapsed = 0.0
            var dayOffset = 0.0
            let numReviews = Int.random(in: 6...14, using: &rng)
            for revIdx in 0..<numReviews {
                let reviewedAt = base.addingTimeInterval(Double(cardIdx) * 1_000_000 + dayOffset * 86_400)
                let rating: Rating
                if revIdx == 0 {
                    rating = firstRatings.randomElement(using: &rng)!
                } else {
                    let r = engine.forgettingCurve(elapsedDays: elapsed, stability: s)
                    let pass = Double.random(in: 0..<1, using: &rng) < r
                    rating = pass ? passRatings.randomElement(using: &rng)! : .again
                }
                rows.append(OptimizationReviewLogRow(
                    cardID: cardID, reviewedAt: reviewedAt, rating: rating, elapsedDays: elapsed))
                let ds = engine.nextMemoryState(d: d, s: s, t: Int(elapsed), g: rating)
                d = ds.d; s = ds.s
                let interval = max(1.0, s * 0.5)
                let jitter = Double.random(in: 0.8..<1.2, using: &rng)
                let advance = interval * jitter
                dayOffset += advance
                elapsed = advance
            }
        }
        return OptimizationDataset(rows: rows)
    }

    static func calibration(_ dataset: OptimizationDataset, parameters: FSRSParameters)
        -> (meanPredicted: Double, meanActual: Double) {
        let engine = LiveFSRS6Engine(parameters: parameters)
        var sumPred = 0.0, sumActual = 0.0, count = 0
        for seq in dataset.cardSequences {
            var d = 0.0, s = 0.0
            for (idx, sample) in seq.enumerated() {
                if idx > 0 && !sample.sameDay && s > 0 {
                    let r = min(max(engine.forgettingCurve(elapsedDays: sample.elapsedDays, stability: s), 1e-7), 1 - 1e-7)
                    sumPred += r
                    sumActual += (sample.rating == .again) ? 0.0 : 1.0
                    count += 1
                }
                let ds = engine.nextMemoryState(d: d, s: s, t: Int(sample.elapsedDays), g: sample.rating)
                d = ds.d; s = ds.s
            }
        }
        guard count > 0 else { return (0, 0) }
        return (sumPred / Double(count), sumActual / Double(count))
    }
}
