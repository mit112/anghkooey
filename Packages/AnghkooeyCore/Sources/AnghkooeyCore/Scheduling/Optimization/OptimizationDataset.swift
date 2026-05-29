import Foundation

/// Replay-based training dataset. Placeholder — filled in T1.
public struct OptimizationDataset: Sendable, Equatable {
    public let cardSequences: [[ReviewSample]]
    public init(cardSequences: [[ReviewSample]] = []) { self.cardSequences = cardSequences }
    public var eligibleSampleCount: Int { 0 }
}
