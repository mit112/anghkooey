/// Test/preview implementation of `ClozeAuthoringService`.
public final class MockClozeAuthoringService: ClozeAuthoringService, @unchecked Sendable {
    public var stubbed: [ClozeDraft] = []

    public init() {}

    public var availability: AuthoringAvailability { get async { .available } }

    public func generateClozeDrafts(from text: String) async throws -> AsyncThrowingStream<ClozeDraft, Error> {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AuthoringError.emptyInput
        }
        let drafts = stubbed
        return AsyncThrowingStream { continuation in
            for draft in drafts { continuation.yield(draft) }
            continuation.finish()
        }
    }
}
