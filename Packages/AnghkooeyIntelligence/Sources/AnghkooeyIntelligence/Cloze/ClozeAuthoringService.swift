/// Contract for on-device AI cloze markup authoring.
public protocol ClozeAuthoringService: Sendable {
    var availability: AuthoringAvailability { get async }

    /// Begin streaming AI-proposed cloze drafts for the given passage.
    ///
    /// - Throws: `AuthoringError.emptyInput` if `text` is blank.
    func generateClozeDrafts(from text: String) async throws -> AsyncThrowingStream<ClozeDraft, Error>
}
