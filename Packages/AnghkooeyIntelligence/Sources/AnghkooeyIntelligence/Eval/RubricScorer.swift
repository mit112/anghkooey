import Foundation

/// Pure-string rubric scorer for `CardDraft` quality.
///
/// All four criteria must pass for a card to pass (binary, no averaging).
/// See strategic plan §4.2 for the locked scoring contract.
public enum RubricScorer {

    /// Binary rubric result for a single `CardDraft`.
    ///
    /// All four criteria must be `true` for `cardPasses` to return `true`.
    public struct CardResult: Sendable {
        /// Question is ≤ 120 chars and tests exactly one fact (no "and"/"or" conjunctions).
        public var atomic: Bool
        /// Answer is ≥ 4 words and contains no vague references (e.g. "above", "following").
        public var specific: Bool
        /// Every non-stop-word token in the answer appears in the source passage.
        public var groundednessPass: Bool
        /// No 4-gram from the answer appears verbatim in the question.
        public var qNotA: Bool
        /// `true` iff all four criteria pass.
        public var cardPasses: Bool { atomic && specific && groundednessPass && qNotA }
    }

    private static let stopwords: Set<String> = [
        "a", "an", "the", "is", "are", "was", "were", "be", "been", "being",
        "in", "on", "at", "to", "for", "of", "and", "or", "but", "it", "its",
        "this", "that", "with", "by", "from", "as", "into", "through", "during",
        "not", "no", "nor", "so", "yet", "both", "either", "whether", "which",
        "who", "whom", "what", "how", "when", "where", "why", "each", "every",
        "do", "does", "did", "will", "would", "could", "should", "may", "might",
        "has", "have", "had", "can"
    ]

    private static let vagueRefs = ["above", "following", "described", "mentioned"]

    /// Score a single `CardDraft` against its source passage.
    public static func score(draft: CardDraft, passage: String) -> CardResult {
        CardResult(
            atomic: isAtomic(draft.question),
            specific: isSpecific(draft.answer),
            groundednessPass: isGrounded(answer: draft.answer, passage: passage),
            qNotA: questionDoesNotLeakAnswer(question: draft.question, answer: draft.answer)
        )
    }

    /// An input passes iff every card from that input passes.
    public static func inputPasses(drafts: [CardDraft], passage: String) -> Bool {
        drafts.allSatisfy { score(draft: $0, passage: passage).cardPasses }
    }

    // MARK: - Criteria

    private static func isAtomic(_ question: String) -> Bool {
        guard question.count <= 120 else { return false }
        let lower = question.lowercased()
        let conjunctions = [" and ", " or "]
        return !conjunctions.contains { lower.contains($0) }
    }

    private static func isSpecific(_ answer: String) -> Bool {
        let words = answer.split(separator: " ")
        guard words.count >= 4 else { return false }
        let lower = answer.lowercased()
        return !vagueRefs.contains { lower.contains($0) }
    }

    private static func isGrounded(answer: String, passage: String) -> Bool {
        let passageLower = passage.lowercased()
        let answerTokens = answer.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty && !stopwords.contains($0) }
        // TODO: uses substring match, not whole-word — "cat" satisfies "catecholamine". Upgrade to word-boundary regex for v2.
        return answerTokens.allSatisfy { passageLower.contains($0) }
    }

    private static func questionDoesNotLeakAnswer(question: String, answer: String) -> Bool {
        let qWords = question.lowercased().split(separator: " ").map(String.init)
        let aWords = answer.lowercased().split(separator: " ").map(String.init)
        guard aWords.count >= 4 else { return true } // < 4 words can't form a 4-gram; skip check
        for i in 0...(aWords.count - 4) {
            let gram = aWords[i..<(i + 4)].joined(separator: " ")
            if qWords.joined(separator: " ").contains(gram) { return false }
        }
        return true
    }
}
