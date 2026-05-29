import Testing
@testable import AnghkooeyCore

@Suite struct ClozeMarkupParserTests {

    struct ParseCase: Sendable {
        let markup: String
        let expectedIndices: [Int]
        let expectedAnswers: [String]
    }

    static let valid: [ParseCase] = [
        .init(markup: "The {{c1::mitochondria}} is the {{c2::powerhouse}} of the cell",
              expectedIndices: [1, 2], expectedAnswers: ["mitochondria", "powerhouse"]),
        .init(markup: "{{c1::Paris}} is the capital of France",
              expectedIndices: [1], expectedAnswers: ["Paris"]),
        .init(markup: "Water is {{c1::H2O::chemical formula}}",
              expectedIndices: [1], expectedAnswers: ["H2O"]),
    ]

    @Test(arguments: valid) func parsesValidMarkup(_ c: ParseCase) throws {
        let t = try ClozeMarkupParser.parse(c.markup)
        #expect(t.indices == c.expectedIndices)
        #expect(t.deletions.map(\.answer) == c.expectedAnswers)
    }

    @Test func parsesHint() throws {
        let t = try ClozeMarkupParser.parse("Water is {{c1::H2O::chemical formula}}")
        #expect(t.deletions.first?.hint == "chemical formula")
    }

    @Test func rendersQuestionHidingTargetRevealingSiblings() throws {
        let t = try ClozeMarkupParser.parse("The {{c1::mitochondria}} is the {{c2::powerhouse}} of the cell")
        #expect(ClozeMarkupParser.renderQuestion(t, index: 1) == "The […] is the powerhouse of the cell")
        #expect(ClozeMarkupParser.renderQuestion(t, index: 2) == "The mitochondria is the […] of the cell")
    }

    @Test func rendersAnswer() throws {
        let t = try ClozeMarkupParser.parse("The {{c1::mitochondria}} is the {{c2::powerhouse}} of the cell")
        #expect(ClozeMarkupParser.renderAnswer(t, index: 1) == "mitochondria")
    }

    @Test func rejectsNoDeletions() {
        #expect(throws: ClozeParseError.noDeletions) { try ClozeMarkupParser.parse("plain text") }
    }
    @Test func rejectsUnclosed() {
        #expect(throws: ClozeParseError.unclosedMarker) { try ClozeMarkupParser.parse("a {{c1::b") }
    }
    @Test func rejectsDuplicateIndex() {
        #expect(throws: ClozeParseError.duplicateIndex(1)) {
            try ClozeMarkupParser.parse("{{c1::a}} and {{c1::b}}")
        }
    }
    @Test func rejectsEmptyAnswer() {
        #expect(throws: ClozeParseError.emptyAnswer(index: 1)) { try ClozeMarkupParser.parse("{{c1::}}") }
    }
    @Test func rejectsNonPositiveIndex() {
        #expect(throws: ClozeParseError.nonPositiveIndex(0)) { try ClozeMarkupParser.parse("{{c0::a}}") }
    }
    @Test func rejectsNestedMarker() {
        #expect(throws: ClozeParseError.nestedMarker) {
            try ClozeMarkupParser.parse("{{c1::{{c2::nested}}}}")
        }
    }
    @Test func rejectsTooManyDeletions() throws {
        let markup = (1...21).map { "{{c\($0)::word\($0)}}" }.joined(separator: " ")
        #expect(throws: ClozeParseError.tooManyDeletions(count: 21, max: 20)) {
            try ClozeMarkupParser.parse(markup)
        }
    }
}
