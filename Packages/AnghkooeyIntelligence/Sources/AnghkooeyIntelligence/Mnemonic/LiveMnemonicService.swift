import FoundationModels
import OSLog

/// Structured output type for `LiveMnemonicService`.
///
/// `@Generable` makes all fields Optional in `PartiallyGenerated` — access
/// `snapshot.content.mnemonic` (type `String?`) during streaming.
@Generable
public struct MnemonicResponse: Sendable {
    public var mnemonic: String
}

/// Production `MnemonicService` backed by `LanguageModelSession`.
///
/// Verified API shapes (from `FoundationModels.swiftinterface`, Xcode 26 beta):
/// - `session.streamResponse(to: prompt, generating: MnemonicResponse.self)`
/// - Each element is a `Snapshot`; `snapshot.content` is `MnemonicResponse.PartiallyGenerated`
/// - `snapshot.content.mnemonic` is `String?`; non-nil in the final snapshot
public struct LiveMnemonicService: MnemonicService {

    private static let instructions = """
        You are a mnemonic creator for spaced-repetition flashcards. \
        Given a question and its answer, write a short, vivid memory device \
        (concrete image, acronym, rhyme, or micro-story) that makes the answer \
        impossible to forget. Rules:
        - Exactly 1–2 sentences. No longer.
        - Concrete and specific — no generic study advice like "repeat this often".
        - Do not copy the question or answer verbatim.
        - Output only the mnemonic, nothing else.
        """

    private let log = IntelligenceLog.authoring

    public init() {}

    public var availability: AuthoringAvailability {
        get async {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(.deviceNotEligible):
                return .unavailable(reason: .deviceNotEligible)
            case .unavailable(.appleIntelligenceNotEnabled):
                return .unavailable(reason: .appleIntelligenceNotEnabled)
            case .unavailable(.modelNotReady):
                return .unavailable(reason: .modelNotReady)
            @unknown default:
                return .unavailable(reason: .modelNotReady)
            }
        }
    }

    public func generateMnemonic(question: String, answer: String) async throws -> String {
        guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AuthoringError.emptyInput
        }
        let avail = await availability
        if case .unavailable(let reason) = avail {
            throw AuthoringError.unavailable(reason: reason)
        }
        log.debug("Generating mnemonic for: \(question, privacy: .public)")
        let prompt = "Question: \(question)\nAnswer: \(answer)"
        let session = LanguageModelSession(instructions: Self.instructions)
        let stream = session.streamResponse(to: prompt, generating: MnemonicResponse.self)

        var result: String?
        for try await snapshot in stream {
            // Collect the latest non-empty partial; the final iteration has the complete text.
            if let text = snapshot.content.mnemonic, !text.isEmpty {
                result = text
            }
        }

        guard let mnemonic = result else {
            throw AuthoringError.generationFailed(underlying: MnemonicServiceError.emptyResponse)
        }
        log.debug("Mnemonic ready (\(mnemonic.count, privacy: .public) chars)")
        return mnemonic
    }
}

private enum MnemonicServiceError: Error {
    case emptyResponse
}
