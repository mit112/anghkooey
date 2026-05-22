/// Contract for on-device mnemonic generation.
///
/// Both `LiveMnemonicService` (FoundationModels) and `MockMnemonicService`
/// (deterministic) conform. Callers depend only on this protocol — no
/// FoundationModels types cross the module boundary.
public protocol MnemonicService: Sendable {

    /// Runtime availability of the underlying language model.
    var availability: AuthoringAvailability { get async }

    /// Generates a mnemonic memory device for the given flashcard.
    ///
    /// - Throws: `AuthoringError.unavailable` if the model is not ready.
    /// - Throws: `AuthoringError.generationFailed` on model errors.
    /// - Returns: A 1–2 sentence mnemonic string.
    func generateMnemonic(question: String, answer: String) async throws -> String
}
