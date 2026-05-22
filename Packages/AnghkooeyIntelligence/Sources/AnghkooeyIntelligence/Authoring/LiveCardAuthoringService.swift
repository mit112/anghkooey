import FoundationModels
import OSLog

/// Production implementation of `CardAuthoringService` backed by
/// `LanguageModelSession` (FoundationModels / Apple Intelligence).
///
/// API notes verified against arm64-apple-ios-simulator.swiftinterface (Xcode 26 beta):
/// - `ResponseStream<Content>` iteration yields `Snapshot` values.
/// - `Snapshot.content` is `Content.PartiallyGenerated` — access is
///   `snapshot.content.drafts`, not `snapshot.drafts`.
/// - `SystemLanguageModel.Availability` cases: `.available` and
///   `.unavailable(UnavailableReason)` where reason is
///   `.deviceNotEligible`, `.appleIntelligenceNotEnabled`, or `.modelNotReady`.
/// - `LanguageModelSession.init` accepts `instructions: String?`.
public struct LiveCardAuthoringService: CardAuthoringService {

    // MARK: - System prompt

    private static let instructions = """
        You are a spaced-repetition card author. Given a passage of text, generate \
        atomic question-and-answer flashcard pairs that test recall of specific facts \
        in the passage. Rules:
        - Each card tests exactly one fact.
        - Do not invent or infer facts not present in the passage.
        - Questions must be specific enough that only someone who read the passage \
          can answer them.
        - Answers must be concise (1–2 sentences maximum).
        - The question must not contain or restate the answer.
        - Propose 1–3 relevant topic tags per card (lowercase, no spaces).
        Return only cards derivable from the passage. If the passage contains no \
        memorable facts, return an empty list.
        """

    // MARK: - Private state

    private let log = IntelligenceLog.authoring

    // MARK: - Init

    public init() {}

    // MARK: - CardAuthoringService

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

    public func generateDrafts(from text: String) async throws -> AsyncThrowingStream<CardDraft, Error> {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AuthoringError.emptyInput
        }
        let avail = await availability
        if case .unavailable(let reason) = avail {
            throw AuthoringError.unavailable(reason: reason)
        }
        log.debug("Starting generation for passage of \(text.count, privacy: .public) chars")

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let session = LanguageModelSession(instructions: Self.instructions)
                    let stream = session.streamResponse(to: text, generating: AuthorResponse.self)
                    var accumulator = SnapshotAccumulator()

                    // Each element from ResponseStream<AuthorResponse> is a Snapshot
                    // with `content: AuthorResponse.PartiallyGenerated`.
                    // Access `snapshot.content.drafts` to reach [CardDraft.PartiallyGenerated].
                    for try await snapshot in stream {
                        // snapshot.content is AuthorResponse.PartiallyGenerated.
                        // snapshot.content.drafts is Optional<[CardDraft.PartiallyGenerated]>:
                        //   @Generable wraps all fields as Optional in the PartiallyGenerated
                        //   nested struct to represent fields that haven't streamed in yet.
                        // CardDraft.PartiallyGenerated fields are all Optional<T>.
                        let partials: [SnapshotAccumulator.PartialDraft] = (snapshot.content.drafts ?? []).compactMap { (partial: CardDraft.PartiallyGenerated) -> SnapshotAccumulator.PartialDraft? in
                            guard let q = partial.question, let a = partial.answer, !q.isEmpty, !a.isEmpty else { return nil }
                            return SnapshotAccumulator.PartialDraft(
                                question: q,
                                answer: a,
                                proposedTags: partial.proposedTags ?? [],
                                sourceSpan: partial.sourceSpan
                            )
                        }
                        for draft in accumulator.update(partials) {
                            log.debug("Emitting draft: \(draft.question, privacy: .public)")
                            continuation.yield(draft)
                        }
                    }
                    log.debug("Generation stream finished")
                    continuation.finish()
                } catch {
                    log.error("Generation failed: \(error, privacy: .public)")
                    continuation.finish(
                        throwing: AuthoringError.generationFailed(underlying: error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
