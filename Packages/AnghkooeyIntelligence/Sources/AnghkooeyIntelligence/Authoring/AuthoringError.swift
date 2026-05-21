/// Errors thrown by `CardAuthoringService.generateDrafts(from:)`.
public enum AuthoringError: Error, Sendable, Equatable {
    /// The input text was empty or whitespace-only.
    case emptyInput
    /// The on-device model is not available. Inspect `reason` to drive UX.
    case unavailable(reason: AuthoringAvailability.UnavailableReason)
    /// FoundationModels threw an error during generation.
    /// Inspect `underlying` for retry decisions (e.g. `.rateLimited`).
    case generationFailed(underlying: Error)

    public static func == (lhs: AuthoringError, rhs: AuthoringError) -> Bool {
        switch (lhs, rhs) {
        case (.emptyInput, .emptyInput): return true
        case (.unavailable(let l), .unavailable(let r)): return l == r
        case (.generationFailed, .generationFailed): return true // Error is not Equatable; any two generationFailed(_:) compare equal
        default: return false
        }
    }
}
