import Testing
@testable import AnghkooeyUI
import AnghkooeyCore

@Suite struct ReviewSummaryTests {
    @Test func computesAccuracyFromRatings() {
        var s = ReviewSummary()
        s.record(.good); s.record(.easy); s.record(.again); s.record(.hard)
        #expect(s.reviewed == 4)
        #expect(s.accuracyPercent == 50)
    }
    @Test func emptySummaryIsZero() {
        let s = ReviewSummary()
        #expect(s.reviewed == 0)
        #expect(s.accuracyPercent == 0)
    }
}
