/// Runtime availability of the on-device AI authoring model.
///
/// Maps `SystemLanguageModel.availability` into a stable product-level enum
/// so the UI layer can make UX decisions without importing FoundationModels.
public enum AuthoringAvailability: Sendable, Equatable {
    case available
    case unavailable(reason: UnavailableReason)

    /// The reason the model is not available.
    ///
    /// - `deviceNotEligible`: hardware does not support Apple Intelligence.
    /// - `appleIntelligenceNotEnabled`: user has not enabled it in Settings.
    /// - `modelNotReady`: eligible device but model not yet downloaded.
    public enum UnavailableReason: Sendable, Equatable {
        case deviceNotEligible
        case appleIntelligenceNotEnabled
        case modelNotReady
    }
}
