import Testing
@testable import AnghkooeyIntelligence

@Suite("RubricScorer")
struct RubricScorerTests {

    let passage = "Mitosis is the process by which a cell divides into two identical daughter cells."

    @Test("atomic: compound question with 'and' fails")
    func atomicFailConjunction() {
        let draft = CardDraft(question: "What is mitosis and how many daughter cells does it produce?",
                              answer: "Cell division producing two identical daughters.")
        let result = RubricScorer.score(draft: draft, passage: passage)
        #expect(!result.atomic)
    }

    @Test("atomic: question >120 chars fails")
    func atomicFailLength() {
        let long = String(repeating: "word ", count: 25)  // >120 chars
        let draft = CardDraft(question: long, answer: "A")
        let result = RubricScorer.score(draft: draft, passage: passage)
        #expect(!result.atomic)
    }

    @Test("atomic: short single-fact question passes")
    func atomicPass() {
        let draft = CardDraft(question: "What process produces two identical daughter cells?",
                              answer: "Mitosis")
        let result = RubricScorer.score(draft: draft, passage: passage)
        #expect(result.atomic)
    }

    @Test("specific: answer shorter than 4 words fails")
    func specificFailShort() {
        let draft = CardDraft(question: "Q?", answer: "Yes")
        let result = RubricScorer.score(draft: draft, passage: passage)
        #expect(!result.specific)
    }

    @Test("specific: answer containing vague reference fails")
    func specificFailVague() {
        let draft = CardDraft(question: "Q?",
                              answer: "The process described above produces daughter cells.")
        let result = RubricScorer.score(draft: draft, passage: passage)
        #expect(!result.specific)
    }

    @Test("specific: concrete answer passes")
    func specificPass() {
        let draft = CardDraft(question: "Q?",
                              answer: "Mitosis produces two identical daughter cells.")
        let result = RubricScorer.score(draft: draft, passage: passage)
        #expect(result.specific)
    }

    @Test("groundedness: token not in passage fails")
    func groundednessFailHallucination() {
        let draft = CardDraft(question: "Q?",
                              answer: "Mitosis occurs during interphase of the cell cycle.")
        // "interphase" not in passage
        let result = RubricScorer.score(draft: draft, passage: passage)
        #expect(!result.groundednessPass)
    }

    @Test("groundedness: all tokens in passage passes")
    func groundednessPass() {
        let draft = CardDraft(question: "Q?",
                              answer: "Mitosis divides a cell into two identical daughter cells.")
        let result = RubricScorer.score(draft: draft, passage: passage)
        #expect(result.groundednessPass)
    }

    @Test("qNotA: 4-gram from answer in question fails")
    func qNotAFail() {
        let draft = CardDraft(
            question: "What is the process that produces two identical daughter cells?",
            answer: "The process that produces two identical daughter cells is mitosis.")
        let result = RubricScorer.score(draft: draft, passage: passage)
        #expect(!result.qNotA)
    }

    @Test("qNotA: distinct question and answer passes")
    func qNotAPass() {
        let draft = CardDraft(question: "What process divides a cell in two?",
                              answer: "Mitosis produces two identical daughter cells.")
        let result = RubricScorer.score(draft: draft, passage: passage)
        #expect(result.qNotA)
    }

    @Test("cardPasses iff all four criteria pass")
    func cardPassesAllFour() {
        let draft = CardDraft(question: "What process produces two identical daughter cells?",
                              answer: "Mitosis divides a cell into two identical daughters.")
        let result = RubricScorer.score(draft: draft, passage: passage)
        #expect(result.cardPasses == (result.atomic && result.specific &&
                                      result.groundednessPass && result.qNotA))
    }
}
