import Testing
@testable import AnghkooeyCore

@Suite("ReviewGrade — M4.4")
struct ReviewGradeTests {

    @Test("ReviewGrade has exactly 2 cases")
    func caseCount() {
        #expect(ReviewGrade.allCases.count == 2)
    }

    @Test("missed maps to Rating.again")
    func missedMapsToAgain() {
        #expect(ReviewGrade.missed.fsrsRating == .again)
    }

    @Test("gotIt maps to Rating.good")
    func gotItMapsToGood() {
        #expect(ReviewGrade.gotIt.fsrsRating == .good)
    }
}
