import Foundation

/// Errors surfaced by the persistence layer.
public enum PersistenceError: Error, LocalizedError, Sendable {
    /// Building the `Schema` from the versioned schema declaration failed.
    case schemaInitFailed(underlying: Error)
    /// Constructing the `ModelContainer` from the schema + configuration failed.
    case containerCreationFailed(underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .schemaInitFailed(let underlying):
            return "Failed to initialize SwiftData schema: \(underlying.localizedDescription)"
        case .containerCreationFailed(let underlying):
            return "Failed to create SwiftData ModelContainer: \(underlying.localizedDescription)"
        }
    }
}
