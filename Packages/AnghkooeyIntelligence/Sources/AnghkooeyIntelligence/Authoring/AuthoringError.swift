/// Errors thrown by `CardAuthoringService.generateDrafts(from:)`.
public enum AuthoringError: Error, Sendable {
    /// The input text was empty or whitespace-only.
    case emptyInput
    /// The on-device model is not available. Inspect `reason` to drive UX.
    case unavailable(reason: AuthoringAvailability.UnavailableReason)
    /// FoundationModels threw an error during generation.
    /// Inspect `underlying` for retry decisions (e.g. `.rateLimited`).
    case generationFailed(underlying: Error)
}
