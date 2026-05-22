import Testing
@testable import AnghkooeyCore

@Suite("ReviewGrade — M5.5G")
struct ReviewGradeTests {

    @Test("ReviewGrade has exactly 4 cases")
    func caseCount() {
        #expect(ReviewGrade.allCases.count == 4)
    }

    @Test("again maps to Rating.again")
    func againMapsToAgain() {
        #expect(ReviewGrade.again.fsrsRating == .again)
    }

    @Test("hard maps to Rating.hard")
    func hardMapsToHard() {
        #expect(ReviewGrade.hard.fsrsRating == .hard)
    }

    @Test("good maps to Rating.good")
    func goodMapsToGood() {
        #expect(ReviewGrade.good.fsrsRating == .good)
    }

    @Test("easy maps to Rating.easy")
    func easyMapsToEasy() {
        #expect(ReviewGrade.easy.fsrsRating == .easy)
    }
}
