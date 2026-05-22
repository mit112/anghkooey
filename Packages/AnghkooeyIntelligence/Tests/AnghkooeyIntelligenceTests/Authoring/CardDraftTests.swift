import Foundation
import Testing
@testable import AnghkooeyIntelligence

@Suite("CardDraft")
struct CardDraftTests {

    @Test("default init sets empty proposedTags and nil sourceSpan")
    func defaultInit() {
        let draft = CardDraft(question: "Q", answer: "A")
        #expect(draft.proposedTags == [])
        #expect(draft.sourceSpan == nil)
    }

    @Test("Codable round-trip preserves all fields")
    func codableRoundTrip() throws {
        let draft = CardDraft(question: "Q", answer: "A",
                              proposedTags: ["tag1"], sourceSpan: "span")
        let data = try JSONEncoder().encode(draft)
        let decoded = try JSONDecoder().decode(CardDraft.self, from: data)
        #expect(decoded == draft)
    }

    @Test("Equatable: different question → not equal")
    func equatable() {
        let a = CardDraft(question: "Q1", answer: "A")
        let b = CardDraft(question: "Q2", answer: "A")
        #expect(a != b)
    }
}
