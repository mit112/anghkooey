/// Contract for on-device AI card authoring.
///
/// Both `LiveCardAuthoringService` (FoundationModels) and
/// `MockCardAuthoringService` (fixture-replay) conform to this protocol.
/// Callers depend only on this protocol — no FoundationModels types leak
/// through the boundary.
public protocol CardAuthoringService: Sendable {

    /// Runtime availability of the underlying model.
    ///
    /// Check this before presenting the AI capture path in the UI.
    /// When `.unavailable`, the reason drives the explanation shown to the user.
    var availability: AuthoringAvailability { get async }

    /// Begin streaming AI-authored `CardDraft` values for the given passage.
    ///
    /// - Throws: `AuthoringError.emptyInput` if `text` is blank.
    /// - Throws: `AuthoringError.unavailable(reason:)` if the model is not available.
    /// - Throws: `AuthoringError.generationFailed(underlying:)` on model errors.
    /// - Returns: An `AsyncThrowingStream` that yields one `CardDraft` per
    ///   completed Q&A pair as generation progresses.
    func generateDrafts(from text: String) async throws -> AsyncThrowingStream<CardDraft, Error>

    /// Returns a single authored draft for callers that only need one card.
    func author(from text: String) async throws -> CardDraft
}

public extension CardAuthoringService {
    /// Returns the first `CardDraft` from the generation stream.
    ///
    /// Used by `AppState.enqueue` which processes one draft per captured item.
    /// Throws `AuthoringError.generationFailed` if the stream ends without
    /// yielding a single draft (e.g. the model produced nothing).
    func author(from text: String) async throws -> CardDraft {
        let stream = try await generateDrafts(from: text)
        for try await draft in stream {
            return draft
        }
        throw AuthoringError.generationFailed(
            underlying: AuthoringServiceError.emptyStream
        )
    }
}

/// Internal error type for `CardAuthoringService` default implementations.
enum AuthoringServiceError: Error {
    case emptyStream
}
