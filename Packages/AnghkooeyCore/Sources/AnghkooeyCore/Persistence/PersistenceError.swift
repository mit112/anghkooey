import Foundation

/// Errors surfaced by the persistence layer.
public enum PersistenceError: Error, LocalizedError, Sendable {
    /// Building the `Schema` from the versioned schema declaration failed.
    case schemaInitFailed(underlying: Error)
    /// Constructing the `ModelContainer` from the schema + configuration failed.
    case containerCreationFailed(underlying: Error)
    /// `shiftAllDueDates(byDays:)` was called with a negative value.
    case invalidShift(days: Int)

    public var errorDescription: String? {
        switch self {
        case .schemaInitFailed(let underlying):
            return "Failed to initialize SwiftData schema: \(underlying.localizedDescription)"
        case .containerCreationFailed(let underlying):
            return "Failed to create SwiftData ModelContainer: \(underlying.localizedDescription)"
        case .invalidShift(let days):
            return "shiftAllDueDates requires days >= 0; got \(days)"
        }
    }
}
