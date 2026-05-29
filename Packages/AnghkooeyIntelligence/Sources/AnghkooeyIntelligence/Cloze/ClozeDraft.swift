import FoundationModels

// @Generable and Codable coexist intentionally — same pattern as CardDraft.
@Generable
public struct ClozeDraft: Codable, Equatable, Sendable {
    /// Cloze markup using {{cN::answer::hint}} markers.
    public var markedText: String
    /// Proposed lowercase topic tags.
    public var proposedTags: [String]

    public init(markedText: String, proposedTags: [String] = []) {
        self.markedText = markedText
        self.proposedTags = proposedTags
    }
}
