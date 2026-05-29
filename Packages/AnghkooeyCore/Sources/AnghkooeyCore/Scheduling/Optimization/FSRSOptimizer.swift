import Foundation

/// Contract for fitting a personal FSRS-6 weight set to a user's review history.
public protocol FSRSOptimizer: Sendable {
    /// Fit `initial.w` to `dataset`. `progress` is called with values in `0...1`.
    /// Returns the baseline/optimized losses and the fitted parameters.
    func optimize(
        _ dataset: OptimizationDataset,
        from initial: FSRSParameters,
        progress: @Sendable (Double) -> Void
    ) async -> OptimizationResult
}
