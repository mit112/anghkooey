import Foundation
import Testing
// Selective imports to avoid the `Testing.Tag` ↔ `AnghkooeyCore.Tag` collision
// noted in PersistenceTests.swift.
import struct AnghkooeyCore.FSRSParameters
import struct AnghkooeyCore.SchedulingCard
import struct AnghkooeyCore.SchedulerOutput
import struct AnghkooeyCore.ReviewLogEntry
import struct AnghkooeyCore.LiveFSRS6Engine
import struct AnghkooeyCore.MockFSRS6Engine
import enum AnghkooeyCore.Rating
import enum AnghkooeyCore.CardState
import enum AnghkooeyCore.SchedulingError

// M1 T3 — Contract tests for the scheduling skeleton.
//
// These tests pin the public surface of `Scheduling/`. They are deliberately
// shallow on behaviour because the math port is M1 T4. What we *do* pin:
//
// 1. Type names + property names + property types (compile-time contract).
// 2. The 21-weight `default_w` vector from ADR-0002 byte-for-byte.
// 3. Other `FSRSParameters.default` scalars.
// 4. `Rating.rawValue` still matches the FSRS spec used by ts-fsrs v5.4.0.
// 5. `SchedulingCard.newCard(due:)` starting snapshot.
// 6. `MockFSRS6Engine.next` deterministic transitions per its doc-comment
//    contract — these are what Codex must satisfy when filling the stub.
//
// `LiveFSRS6Engine.next` is NOT exercised here; it traps until T4 lands.

@Suite("FSRSParameters")
struct FSRSParametersContractTests {

    @Test("default w vector matches ADR-0002 byte-for-byte")
    func defaultWeightsMatchADR() {
        let expected: [Double] = [
            0.212, 1.2931, 2.3065, 8.2956, 6.4133, 0.8334, 3.0194, 0.001,
            1.8722, 0.1666, 0.796, 1.4835, 0.0614, 0.2629, 1.6483, 0.6014,
            1.8729, 0.5425, 0.0912, 0.0658, 0.1542,
        ]
        #expect(FSRSParameters.default.w == expected)
        #expect(FSRSParameters.default.w.count == 21)
    }

    @Test("default scalar parameters match ADR-0002")
    func defaultScalarsMatchADR() {
        let p = FSRSParameters.default
        #expect(p.requestRetention == 0.9)
        #expect(p.maximumInterval == 36_500)
        #expect(p.enableFuzz == false)
        #expect(p.enableShortTerm == true)
        #expect(p.learningStepsSeconds == [60, 600])
        #expect(p.relearningStepsSeconds == [600])
    }

    @Test("FSRS6 decay constant lives at w[20]")
    func decayConstantPosition() {
        // Pinned independently of the full-vector assertion so that a future
        // re-ordering of `w` shows up here even if the array equality test is
        // updated in lockstep with the ADR.
        #expect(FSRSParameters.default.w[20] == 0.1542)
    }
}

@Suite("Rating raw values (FSRS spec)")
struct RatingFSRSSpecTests {

    @Test("rating raw values pin to FSRS-6 spec")
    func ratingRawValues() {
        #expect(Rating.again.rawValue == 1)
        #expect(Rating.hard.rawValue == 2)
        #expect(Rating.good.rawValue == 3)
        #expect(Rating.easy.rawValue == 4)
    }
}

@Suite("SchedulingCard")
struct SchedulingCardContractTests {

    @Test("newCard returns the canonical zeroed snapshot")
    func newCardSnapshot() {
        let due = Date(timeIntervalSince1970: 1_800_000_000)
        let c = SchedulingCard.newCard(due: due)
        #expect(c.state == .new)
        #expect(c.stability == 0)
        #expect(c.difficulty == 0)
        #expect(c.due == due)
        #expect(c.reps == 0)
        #expect(c.lapses == 0)
        #expect(c.learningSteps == 0)
        #expect(c.scheduledDays == 0)
        #expect(c.elapsedDays == 0)
        #expect(c.lastReview == nil)
    }

    @Test("SchedulingCard is a value type (mutation does not alias)")
    func valueSemantics() {
        var a = SchedulingCard.newCard(due: .distantFuture)
        let b = a
        a.reps = 5
        #expect(b.reps == 0)
    }
}

@Suite("LiveFSRS6Engine skeleton")
struct LiveFSRS6EngineContractTests {

    @Test("constructs with default parameters")
    func constructsWithDefaults() {
        let engine = LiveFSRS6Engine()
        #expect(engine.parameters.w == FSRSParameters.default.w)
    }

    @Test("constructs with a custom parameter set")
    func constructsWithCustomParameters() {
        let custom = FSRSParameters(
            w: Array(repeating: 0.0, count: 21),
            requestRetention: 0.85,
            maximumInterval: 100,
            enableFuzz: true,
            enableShortTerm: false,
            learningStepsSeconds: [30],
            relearningStepsSeconds: [120]
        )
        let engine = LiveFSRS6Engine(parameters: custom)
        #expect(engine.parameters == custom)
    }

    // NOTE: We do not call `engine.next(...)` — it traps until M1 T4 lands.
}

@Suite("MockFSRS6Engine contract (Codex must satisfy this)")
struct MockFSRS6EngineContractTests {

    private func newCardAt(_ now: Date) -> SchedulingCard {
        SchedulingCard.newCard(due: now)
    }

    @Test("good on a new card → review, +1 day, scheduledDays=1, reps=1")
    func goodOnNewCard() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let engine = MockFSRS6Engine()
        let out = try engine.next(card: newCardAt(now), rating: .good, now: now)
        #expect(out.card.state == .review)
        #expect(out.card.reps == 1)
        #expect(out.card.lapses == 0)
        #expect(out.card.scheduledDays == 1)
        #expect(out.card.due == now.addingTimeInterval(86_400))
        #expect(out.card.lastReview == now)
        #expect(out.log.rating == .good)
        #expect(out.log.stateBefore == .new)
        #expect(out.log.reviewedAt == now)
    }

    @Test("easy on a new card → review, +4 days, scheduledDays=4")
    func easyOnNewCard() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let engine = MockFSRS6Engine()
        let out = try engine.next(card: newCardAt(now), rating: .easy, now: now)
        #expect(out.card.state == .review)
        #expect(out.card.scheduledDays == 4)
        #expect(out.card.due == now.addingTimeInterval(4 * 86_400))
    }

    @Test("hard on a new card → review, +600s, scheduledDays=0, no lapse")
    func hardOnNewCard() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let engine = MockFSRS6Engine()
        let out = try engine.next(card: newCardAt(now), rating: .hard, now: now)
        #expect(out.card.state == .review)
        #expect(out.card.scheduledDays == 0)
        #expect(out.card.due == now.addingTimeInterval(600))
        #expect(out.card.lapses == 0)
    }

    @Test("again on a new card → relearning, +600s, lapses=1")
    func againOnNewCard() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let engine = MockFSRS6Engine()
        let out = try engine.next(card: newCardAt(now), rating: .again, now: now)
        #expect(out.card.state == .relearning)
        #expect(out.card.lapses == 1)
        #expect(out.card.due == now.addingTimeInterval(600))
        #expect(out.card.scheduledDays == 0)
    }

    @Test("elapsedDays is computed from card.lastReview")
    func elapsedDaysFromLastReview() throws {
        let lastReview = Date(timeIntervalSince1970: 1_800_000_000)
        let now = lastReview.addingTimeInterval(3 * 86_400) // 3 full days
        var card = SchedulingCard.newCard(due: lastReview)
        card.lastReview = lastReview
        card.state = .review
        card.scheduledDays = 2
        card.stability = 5
        card.difficulty = 6

        let engine = MockFSRS6Engine()
        let out = try engine.next(card: card, rating: .good, now: now)

        #expect(out.card.elapsedDays == 3)
        #expect(out.log.elapsedDays == 3)
        #expect(out.log.stabilityBefore == 5)
        #expect(out.log.difficultyBefore == 6)
        #expect(out.log.scheduledDays == 2)
    }

    @Test("rejects now < lastReview with reviewedBeforeLastReview")
    func rejectsClockSkew() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var card = SchedulingCard.newCard(due: now)
        card.lastReview = now.addingTimeInterval(60)
        let engine = MockFSRS6Engine()
        #expect(throws: SchedulingError.reviewedBeforeLastReview) {
            _ = try engine.next(card: card, rating: .good, now: now)
        }
    }
}
