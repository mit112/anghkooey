import FoundationModels
import OSLog

/// Production implementation of `ClozeAuthoringService` backed by
/// `LanguageModelSession` (FoundationModels / Apple Intelligence).
public struct LiveClozeAuthoringService: ClozeAuthoringService {

    private static let instructions = """
        You are a spaced-repetition cloze author. Given a passage, return it with the \
        most salient facts wrapped in Anki-style cloze markers {{c1::answer}}, \
        {{c2::answer}}, … Rules:
        - Each deletion hides exactly one fact.
        - Number deletions sequentially from c1.
        - Never nest markers.
        - Do not invent facts.
        - Propose 1–3 lowercase tags.
        If no memorable facts exist, return an empty list.
        """

    private let log = IntelligenceLog.authoring

    public init() {}

    public var availability: AuthoringAvailability {
        get async {
            switch SystemLanguageModel.default.availability {
            case .available: return .available
            case .unavailable(.deviceNotEligible): return .unavailable(reason: .deviceNotEligible)
            case .unavailable(.appleIntelligenceNotEnabled): return .unavailable(reason: .appleIntelligenceNotEnabled)
            case .unavailable(.modelNotReady): return .unavailable(reason: .modelNotReady)
            @unknown default: return .unavailable(reason: .modelNotReady)
            }
        }
    }

    public func generateClozeDrafts(from text: String) async throws -> AsyncThrowingStream<ClozeDraft, Error> {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AuthoringError.emptyInput
        }
        let avail = await availability
        if case .unavailable(let reason) = avail {
            throw AuthoringError.unavailable(reason: reason)
        }
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let session = LanguageModelSession(instructions: Self.instructions)
                    let stream = session.streamResponse(to: text, generating: ClozeResponse.self)
                    var seen = 0
                    for try await snapshot in stream {
                        let partials = snapshot.content.items ?? []
                        for partial in partials.dropFirst(seen) {
                            guard let marked = partial.markedText, !marked.isEmpty else { continue }
                            continuation.yield(ClozeDraft(
                                markedText: marked,
                                proposedTags: partial.proposedTags ?? []
                            ))
                        }
                        seen = partials.count
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: AuthoringError.generationFailed(underlying: error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
