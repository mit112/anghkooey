/// Test/preview implementation of `ClozeAuthoringService`.
public final class MockClozeAuthoringService: ClozeAuthoringService, @unchecked Sendable {
    public var stubbed: [ClozeDraft] = []

    /// Availability reported by `availability` and consulted by
    /// `generateClozeDrafts(from:)`. Set to `.unavailable(reason:)` to
    /// script the "AI unavailable on this device" path without a real
    /// device/model (#25).
    public var configuredAvailability: AuthoringAvailability = .available

    /// When set, `generateClozeDrafts(from:)` throws
    /// `AuthoringError.generationFailed(underlying: error)` instead of
    /// streaming `stubbed` — lets tests script a generic generation
    /// failure (#25).
    public var error: Error?

    public init() {}

    public var availability: AuthoringAvailability { get async { configuredAvailability } }

    public func generateClozeDrafts(from text: String) async throws -> AsyncThrowingStream<ClozeDraft, Error> {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AuthoringError.emptyInput
        }
        if case .unavailable(let reason) = configuredAvailability {
            throw AuthoringError.unavailable(reason: reason)
        }
        if let error {
            throw AuthoringError.generationFailed(underlying: error)
        }
        let drafts = stubbed
        return AsyncThrowingStream { continuation in
            for draft in drafts { continuation.yield(draft) }
            continuation.finish()
        }
    }
}
