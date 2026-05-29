import Foundation

/// Deterministic stub for UI/integration tests. Reports a fixed improvement
/// and emits a few progress ticks.
public struct MockFSRSOptimizer: FSRSOptimizer {
    public var result: OptimizationResult

    public init(result: OptimizationResult? = nil) {
        self.result = result ?? OptimizationResult(
            baselineLoss: 0.50,
            optimizedLoss: 0.42,
            optimizedParameters: .default,
            weightDeltas: Array(repeating: 0, count: 21),
            achievedRetention: 0.9
        )
    }

    public func optimize(
        _ dataset: OptimizationDataset,
        from initial: FSRSParameters,
        progress: @Sendable (Double) -> Void
    ) async -> OptimizationResult {
        for tick in 1...4 { progress(Double(tick) / 4.0) }
        return result
    }
}
