import FoundationModels

/// A candidate Q&A flashcard produced by the AI authoring pipeline.
///
/// `CardDraft` is the output unit of `CardAuthoringService`. It does not
/// map to `Card` directly — conversion happens in `AnghkooeyUI` after the
/// user reviews and accepts the draft.
@Generable
public struct CardDraft: Sendable, Codable, Equatable {
    /// The recall prompt shown to the user during review.
    public var question: String
    /// The expected answer.
    public var answer: String
    /// AI-proposed tag names (lowercase, no spaces). User edits before persistence.
    public var proposedTags: [String]
    /// The verbatim excerpt from the source passage this card was derived from.
    /// `nil` when the model cannot isolate a single span.
    public var sourceSpan: String?

    public init(question: String,
                answer: String,
                proposedTags: [String] = [],
                sourceSpan: String? = nil) {
        self.question = question
        self.answer = answer
        self.proposedTags = proposedTags
        self.sourceSpan = sourceSpan
    }
}
