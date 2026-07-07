import Foundation

/// Deterministic in-memory stub of `OptimizedParametersStoring` for tests.
///
/// Records every save so a test can assert persistence actually happened,
/// and can be scripted to fail so the save-failure path (#27) is testable
/// without touching the filesystem-backed `OptimizedParametersStore`.
public final class MockOptimizedParametersStore: OptimizedParametersStoring, @unchecked Sendable {
    public private(set) var savedParameters: [FSRSParameters] = []
    public var saveError: Error?

    public init() {}

    public func save(_ parameters: FSRSParameters) throws {
        if let err = saveError { throw err }
        savedParameters.append(parameters)
    }
}
