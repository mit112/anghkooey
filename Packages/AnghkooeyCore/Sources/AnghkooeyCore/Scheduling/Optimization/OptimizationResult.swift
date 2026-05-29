import Foundation

/// Outcome of one optimization run. Surfaced to the UI as the before/after summary.
public struct OptimizationResult: Equatable, Sendable {
    /// Mean BCE loss over eligible samples under `FSRSParameters.default`.
    public let baselineLoss: Double
    /// Mean BCE loss over eligible samples under `optimizedParameters`.
    public let optimizedLoss: Double
    /// The fitted parameter set (default with optimized `w`).
    public let optimizedParameters: FSRSParameters
    /// Per-weight delta `optimized.w[i] - initial.w[i]` (length 21).
    public let weightDeltas: [Double]
    /// Mean predicted recall over eligible samples under `optimizedParameters`
    /// (the model's achieved retention on the user's own history).
    public let achievedRetention: Double

    public init(
        baselineLoss: Double,
        optimizedLoss: Double,
        optimizedParameters: FSRSParameters,
        weightDeltas: [Double],
        achievedRetention: Double
    ) {
        self.baselineLoss = baselineLoss
        self.optimizedLoss = optimizedLoss
        self.optimizedParameters = optimizedParameters
        self.weightDeltas = weightDeltas
        self.achievedRetention = achievedRetention
    }
}
