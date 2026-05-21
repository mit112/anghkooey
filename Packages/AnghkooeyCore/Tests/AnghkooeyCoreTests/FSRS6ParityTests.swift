import Foundation
import Testing
@testable import AnghkooeyCore

// M1 T5 — Parity harness driving LiveFSRS6Engine step-by-step over all
// 150 fixtures from fsrs6-parity.json and comparing against ts-fsrs v5.4.0
// ground truth per ADR-0002 §epsilon.
//
// Epsilon: stability/difficulty within 1e-9 absolute; state/reps/lapses/
// learning_steps/scheduled_days exact; due within ±1 second.

// MARK: - Codable types (mirror ADR-0002 §parity-fixture schema)

private struct ParityFile: Codable, Sendable {
    let schemaVersion: Int
    let fixtures: [ParityFixture]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case fixtures
    }
}

struct ParityFixture: Codable, Sendable, CustomTestStringConvertible {
    let id: String
    let epochISO: String
    let steps: [ParityStep]

    var testDescription: String { id }

    enum CodingKeys: String, CodingKey {
        case id
        case epochISO = "epoch_iso"
        case steps
    }
}

struct ParityStep: Codable, Sendable {
    let stepIndex: Int
    let absoluteSecondsFromEpoch: Int
    let rating: Int
    let expected: ParityExpected

    enum CodingKeys: String, CodingKey {
        case stepIndex = "step_index"
        case absoluteSecondsFromEpoch = "absolute_seconds_from_epoch"
        case rating
        case expected
    }
}

struct ParityExpected: Codable, Sendable {
    let stability: Double
    let difficulty: Double
    let state: Int
    let dueSecondsFromEpoch: Int
    let scheduledDays: Int
    let reps: Int
    let lapses: Int
    let learningSteps: Int

    enum CodingKeys: String, CodingKey {
        case stability
        case difficulty
        case state
        case dueSecondsFromEpoch = "due_seconds_from_epoch"
        case scheduledDays = "scheduled_days"
        case reps
        case lapses
        case learningSteps = "learning_steps"
    }
}

// MARK: - Fixture loader

private func loadParityFixtures() -> [ParityFixture] {
    guard let url = Bundle.module.url(forResource: "fsrs6-parity", withExtension: "json") else {
        preconditionFailure(
            "fsrs6-parity.json not found in test bundle. " +
            "Package.swift must declare resources: [.process(\"Fixtures\")] for AnghkooeyCoreTests."
        )
    }
    do {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ParityFile.self, from: data).fixtures
    } catch {
        preconditionFailure("Failed to decode fsrs6-parity.json: \(error)")
    }
}

// MARK: - Epsilon constants (ADR-0002)

private let epsDouble = 1e-9
private let epsDueSeconds = 1.0

// MARK: - Suite

@Suite("FSRS-6 parity harness")
struct FSRS6ParityTests {

    @Test("fixture step-by-step", arguments: loadParityFixtures())
    func stepByStep(_ fixture: ParityFixture) throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let epoch = formatter.date(from: fixture.epochISO) else {
            Issue.record("Cannot parse epoch_iso '\(fixture.epochISO)' in fixture \(fixture.id)")
            return
        }

        let engine = LiveFSRS6Engine()
        var card = SchedulingCard.newCard(due: epoch)

        for step in fixture.steps {
            let reviewDate = epoch.addingTimeInterval(Double(step.absoluteSecondsFromEpoch))
            guard let rating = Rating(rawValue: step.rating) else {
                Issue.record("[\(fixture.id)] step \(step.stepIndex): invalid rating value \(step.rating)")
                return
            }

            let output = try engine.next(card: card, rating: rating, now: reviewDate)
            let got = output.card
            let exp = step.expected
            let loc = "[\(fixture.id)] step \(step.stepIndex)"

            let stabDelta = abs(got.stability - exp.stability)
            #expect(stabDelta <= epsDouble,
                "\(loc) stability: got=\(got.stability) expected=\(exp.stability) delta=\(stabDelta)")

            let diffDelta = abs(got.difficulty - exp.difficulty)
            #expect(diffDelta <= epsDouble,
                "\(loc) difficulty: got=\(got.difficulty) expected=\(exp.difficulty) delta=\(diffDelta)")

            #expect(got.state.rawValue == exp.state,
                "\(loc) state: got=\(got.state.rawValue) expected=\(exp.state)")

            #expect(got.reps == exp.reps,
                "\(loc) reps: got=\(got.reps) expected=\(exp.reps)")

            #expect(got.lapses == exp.lapses,
                "\(loc) lapses: got=\(got.lapses) expected=\(exp.lapses)")

            #expect(got.learningSteps == exp.learningSteps,
                "\(loc) learning_steps: got=\(got.learningSteps) expected=\(exp.learningSteps)")

            #expect(Int(got.scheduledDays) == exp.scheduledDays,
                "\(loc) scheduled_days: got=\(Int(got.scheduledDays)) expected=\(exp.scheduledDays)")

            let actualDueSec = got.due.timeIntervalSince(epoch)
            let dueDelta = abs(actualDueSec - Double(exp.dueSecondsFromEpoch))
            #expect(dueDelta <= epsDueSeconds,
                "\(loc) due: got=\(actualDueSec)s expected=\(exp.dueSecondsFromEpoch)s delta=\(dueDelta)s")

            card = got
        }
    }
}
