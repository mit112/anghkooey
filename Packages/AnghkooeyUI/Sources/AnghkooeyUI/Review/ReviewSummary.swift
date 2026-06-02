import Foundation
import AnghkooeyCore

/// Accumulates per-session review stats for the session-complete screen.
public struct ReviewSummary: Equatable, Sendable {
    public private(set) var reviewed = 0
    public private(set) var remembered = 0   // good + easy

    public init() {}

    public mutating func record(_ rating: Rating) {
        reviewed += 1
        if rating == .good || rating == .easy { remembered += 1 }
    }

    public var accuracyPercent: Int {
        guard reviewed > 0 else { return 0 }
        return Int((Double(remembered) / Double(reviewed) * 100).rounded())
    }
}
