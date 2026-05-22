/// Deterministic stub of `MnemonicService` for tests and SwiftUI previews.
public struct MockMnemonicService: MnemonicService {

    private let configuredAvailability: AuthoringAvailability
    private let fixedMnemonic: String
    private let error: Error?

    public init(
        mnemonic: String = "Picture a golden gate.",
        availability: AuthoringAvailability = .available,
        error: Error? = nil
    ) {
        self.configuredAvailability = availability
        self.fixedMnemonic = mnemonic
        self.error = error
    }

    public var availability: AuthoringAvailability {
        get async { configuredAvailability }
    }

    public func generateMnemonic(question: String, answer: String) async throws -> String {
        if case .unavailable(let reason) = configuredAvailability {
            throw AuthoringError.unavailable(reason: reason)
        }
        if let error { throw error }
        return fixedMnemonic
    }
}
