import Testing
import Foundation
import SwiftData
@testable import AnghkooeyCore

// MARK: - End-to-end integration test
//
// Tests the full persistence + scheduling seam without the UI layer:
//   create card → dueCards → grade → updated state persists
//
// Note: ReviewSession (AnghkooeyUI) is tested separately in AnghkooeyUITests.
// This test focuses on the CardStore + LiveFSRS6Engine seam.

@Suite("End-to-end review flow — M4.10")
struct EndToEndReviewFlowTests {

    private func makeStore() throws -> CardStore {
        let container = try AnghkooeyModelContainer.makeInMemoryContainer()
        return CardStore(container: container)
    }

    @Test("Full flow: create → due(1) → grade good → due(0) → due(1) at +30 days")
    func fullReviewFlow() async throws {
        let store = try makeStore()
        let engine = LiveFSRS6Engine()
        let now = Date()

        // Step 1: Create a card from a draft (simulates post-authoring acceptance)
        let snap = try await store.create(
            question: "What is the capital of France?",
            answer: "Paris",
            sourceSpan: "France's capital is Paris.",
            now: now
        )

        // Step 2: Card appears in due list immediately
        let dueBefore = try await store.dueCards(asOf: now)
        #expect(dueBefore.count == 1)
        #expect(dueBefore[0].id == snap.id)

        // Step 3: Grade the card with "Got it" (Rating.good)
        let output = try engine.next(card: snap.schedulingCard, rating: .good, now: now)
        try await store.apply(output, to: snap.id, grade: .good, now: now)

        // Step 4: Card is no longer due right now (FSRS pushes it to the future)
        let dueAfterGrade = try await store.dueCards(asOf: now)
        #expect(dueAfterGrade.isEmpty)

        // Step 5: Card becomes due again after the scheduled interval
        let future = now.addingTimeInterval(30 * 24 * 3600)
        let dueInFuture = try await store.dueCards(asOf: future)
        #expect(dueInFuture.count == 1)
        #expect(dueInFuture[0].id == snap.id)

        // Step 6: FSRS fields were persisted correctly
        #expect(dueInFuture[0].stability == output.card.stability)
        #expect(dueInFuture[0].state == output.card.state)

        // M5.A: step-machine state must be persisted, not zero-defaulted.
        let finalDue = try await store.dueCards(asOf: .distantFuture)
        let finalCard = try #require(finalDue.first(where: { $0.id == snap.id }))
        #expect(finalCard.reps >= 1, "reps should increment across reviews")
    }

    @Test("count() returns correct total and due counts")
    func countReturnsCorrectTotalsAndDue() async throws {
        let store = try makeStore()
        let engine = LiveFSRS6Engine()
        let now = Date()

        // Create 3 cards, grade 1
        let a = try await store.create(question: "Q1", answer: "A1", sourceSpan: nil, now: now)
        _ = try await store.create(question: "Q2", answer: "A2", sourceSpan: nil, now: now)
        _ = try await store.create(question: "Q3", answer: "A3", sourceSpan: nil, now: now)

        let beforeGrade = try await store.count(asOf: now)
        #expect(beforeGrade.total == 3)
        #expect(beforeGrade.due == 3)

        let output = try engine.next(card: a.schedulingCard, rating: .good, now: now)
        try await store.apply(output, to: a.id, grade: .good, now: now)

        let afterGrade = try await store.count(asOf: now)
        #expect(afterGrade.total == 3)
        #expect(afterGrade.due == 2)  // card a is deferred
    }
}
