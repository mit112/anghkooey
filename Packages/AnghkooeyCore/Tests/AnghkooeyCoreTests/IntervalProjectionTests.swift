import Testing
import Foundation
@testable import AnghkooeyCore

@Suite struct IntervalProjectionTests {
    @Test func projectsAllFourRatingsForNewCard() throws {
        let engine = LiveFSRS6Engine()
        let card = SchedulingCard(state: .new, stability: 0, difficulty: 0,
                                  due: Date(timeIntervalSince1970: 1_700_000_000),
                                  reps: 0, lapses: 0,
                                  learningSteps: 0,
                                  scheduledDays: 0, elapsedDays: 0,
                                  lastReview: nil)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let projections = IntervalProjection.project(card: card, engine: engine, now: now)

        #expect(projections.count == 4)
        let again = projections[.again]!, hard = projections[.hard]!
        let good = projections[.good]!, easy = projections[.easy]!
        #expect(again <= hard)
        #expect(hard <= good)
        #expect(good <= easy)
    }

    @Test func formatsShortAndLongIntervals() {
        #expect(IntervalProjection.label(seconds: 30) == "<1m")
        #expect(IntervalProjection.label(seconds: 600) == "10m")
        #expect(IntervalProjection.label(seconds: 86_400) == "1d")
        #expect(IntervalProjection.label(seconds: 4 * 86_400) == "4d")
        #expect(IntervalProjection.label(seconds: 45 * 86_400) == "1.5mo")
    }
}
