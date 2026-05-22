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
}
