/// Deterministic fixture-replay implementation of `CardAuthoringService`.
///
/// Used by unit tests and the CI eval harness. Returns the configured
/// `drafts` one by one, or throws `generationFailed` when `error` is set.
public struct MockCardAuthoringService: CardAuthoringService {

    private let configuredAvailability: AuthoringAvailability
    private let drafts: [CardDraft]
    private let error: Error?

    public init(availability: AuthoringAvailability = .available,
                drafts: [CardDraft] = [],
                error: Error? = nil) {
        self.configuredAvailability = availability
        self.drafts = drafts
        self.error = error
    }

    public var availability: AuthoringAvailability {
        get async { configuredAvailability }
    }

    public func generateDrafts(from text: String) async throws -> AsyncThrowingStream<CardDraft, Error> {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AuthoringError.emptyInput
        }
        if case .unavailable(let reason) = configuredAvailability {
            throw AuthoringError.unavailable(reason: reason)
        }
        if let error {
            throw AuthoringError.generationFailed(underlying: error)
        }
        let drafts = self.drafts
        return AsyncThrowingStream { continuation in
            let task = Task {
                for draft in drafts {
                    continuation.yield(draft)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
