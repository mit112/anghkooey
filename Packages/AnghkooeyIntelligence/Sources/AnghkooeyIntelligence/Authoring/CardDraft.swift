import FoundationModels

/// A candidate Q&A flashcard produced by the AI authoring pipeline.
///
/// `CardDraft` is the output unit of `CardAuthoringService`. It does not
/// map to `Card` directly — conversion happens in `AnghkooeyUI` after the
/// user reviews and accepts the draft.
// @Generable and Codable coexist intentionally — verified on Xcode 26 beta.
// If a future beta produces a "redundant conformance" error here, move
// Codable conformance to a separate extension in a non-@Generable file.
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
