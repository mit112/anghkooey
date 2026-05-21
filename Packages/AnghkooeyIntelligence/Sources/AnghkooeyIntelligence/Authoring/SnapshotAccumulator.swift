/// Internal reducer that converts a sequence of `PartiallyGenerated` snapshot
/// arrays into a stream of completed `CardDraft` values.
///
/// `LiveCardAuthoringService` maps `snapshot.content.drafts` to
/// `[PartialDraft]` before calling `update(_:)`, keeping FoundationModels
/// types out of this file and making it fully unit-testable.
struct SnapshotAccumulator {

    /// A plain-value mirror of one `CardDraft.PartiallyGenerated` element.
    struct PartialDraft {
        var question: String
        var answer: String
        var proposedTags: [String]
        var sourceSpan: String?
    }

    private var lastEmittedIndex: Int = -1

    /// Feed the latest partial drafts array; returns newly-completed `CardDraft` values.
    ///
    /// Each array index is emitted at most once — the first time both
    /// `question` and `answer` are non-empty. Stops at the first incomplete
    /// entry so a card that completes late is never silently dropped.
    mutating func update(_ partials: [PartialDraft]) -> [CardDraft] {
        var result: [CardDraft] = []
        let start = lastEmittedIndex + 1
        guard start < partials.count else { return result }
        for i in start..<partials.count {
            let p = partials[i]
            guard !p.question.isEmpty, !p.answer.isEmpty else { break } // stop; revisit next snapshot
            result.append(CardDraft(
                question: p.question,
                answer: p.answer,
                proposedTags: p.proposedTags,
                sourceSpan: p.sourceSpan
            ))
            lastEmittedIndex = i
        }
        return result
    }
}
