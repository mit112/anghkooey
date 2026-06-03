import Testing
import Foundation
@testable import AnghkooeyCore

@Suite("FSRSOptimizer parity vs py-fsrs oracle")
struct FSRSOptimizerParityTests {
    struct Fixture: Codable {
        struct Meta: Codable {
            let eligible_sample_count: Int
            let fsrs_version: String
        }
        struct Review: Codable {
            let card_id: String
            let reviewed_at: String
            let rating: Int
            let elapsed_days: Double
        }
        let meta: Meta
        let reviews: [Review]
        let baseline_loss: Double
        let optimized_loss: Double
        let optimized_w: [Double]
    }

    private func loadFixture() throws -> Fixture {
        let url = Bundle.module.url(forResource: "fsrs-optimizer-parity", withExtension: "json")!
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    /// Deterministic UUIDs from the fixture's string card ids (uuidString form
    /// is irrelevant — only stable grouping matters).
    private func cardUUID(_ id: String, _ cache: inout [String: UUID]) -> UUID {
        if let existing = cache[id] { return existing }
        let new = UUID()
        cache[id] = new
        return new
    }

    private func rows(from fx: Fixture) -> [OptimizationReviewLogRow] {
        let formatter = ISO8601DateFormatter()
        var cache: [String: UUID] = [:]
        return fx.reviews.map { review in
            OptimizationReviewLogRow(
                cardID: cardUUID(review.card_id, &cache),
                reviewedAt: formatter.date(from: review.reviewed_at) ?? Date(timeIntervalSince1970: 0),
                rating: Rating(rawValue: review.rating)!,
                elapsedDays: review.elapsed_days
            )
        }
    }

    @Test("eligible-sample count matches the oracle exactly")
    func eligibleCountParity() throws {
        let fx = try loadFixture()
        let dataset = OptimizationDataset(rows: rows(from: fx))
        #expect(dataset.eligibleSampleCount == fx.meta.eligible_sample_count)
    }

    @Test("baseline loss matches the oracle (same inputs + default w)")
    func baselineParity() throws {
        let fx = try loadFixture()
        let dataset = OptimizationDataset(rows: rows(from: fx))
        let opt = LiveFSRSOptimizer()
        let baseline = opt.meanLoss(dataset, parameters: .default)
        // Same review inputs + identical default weights → identical baseline.
        #expect(abs(baseline - fx.baseline_loss) <= 0.001)
    }

    @Test("optimized loss improvement matches the oracle within tolerance")
    func optimizedLossParity() async throws {
        let fx = try loadFixture()
        let dataset = OptimizationDataset(rows: rows(from: fx))
        let opt = LiveFSRSOptimizer()
        let result = await opt.optimize(dataset, from: .default, progress: { _ in })

        // Optimizer must improve over baseline.
        #expect(result.optimizedLoss <= result.baselineLoss)

        // Loss-based parity (NOT weight equality — different mini-batch RNG paths
        // converge to the same loss basin). Tolerance per plan §Expansion #3:
        // ≤ 0.01 absolute OR ≤ 5% relative, whichever is looser.
        let absoluteOK = abs(result.optimizedLoss - fx.optimized_loss) <= 0.01
        let relativeOK = abs(result.optimizedLoss - fx.optimized_loss) <= 0.05 * fx.optimized_loss
        #expect(absoluteOK || relativeOK,
                "swift optimized=\(result.optimizedLoss) vs oracle=\(fx.optimized_loss)")
    }
}
