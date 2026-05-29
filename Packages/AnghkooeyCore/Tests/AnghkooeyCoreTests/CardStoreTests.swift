import Testing
import Foundation
import SwiftData
@testable import AnghkooeyCore

// MARK: - Helpers

private func makeInMemoryContainer() throws -> ModelContainer {
    try AnghkooeyModelContainer.makeInMemoryContainer()
}

// MARK: - M4.3 contract tests
//
// These tests are RED until Codex replaces the `fatalError` stubs in
// CardStore with real SwiftData implementations.

@Suite("CardStore — M4.3 contract")
struct CardStoreTests {

    // MARK: create_persistsCard_withNewState_andDueNow

    @Test("create persists a card with .new state and dueAt == now")
    func create_persistsCard_withNewState_andDueNow() async throws {
        let container = try makeInMemoryContainer()
        let store = CardStore(container: container)
        let now = Date()

        let snap = try await store.create(
            question: "What is 2 + 2?",
            answer: "4",
            sourceSpan: nil,
            now: now
        )

        #expect(snap.question == "What is 2 + 2?")
        #expect(snap.answer == "4")
        #expect(snap.state == .new)
        #expect(snap.stability == 0)
        #expect(snap.difficulty == 0)
        // dueAt should equal now (card is immediately due)
        #expect(abs(snap.dueAt.timeIntervalSince(now)) < 1)
    }

    // MARK: dueCards_returnsOnlyCardsWithDueAtBeforeOrEqualToNow

    @Test("dueCards returns only cards whose dueAt ≤ now")
    func dueCards_returnsOnlyCardsWithDueAtBeforeOrEqualToNow() async throws {
        let container = try makeInMemoryContainer()
        let store = CardStore(container: container)
        let now = Date()
        let future = now.addingTimeInterval(30 * 24 * 3600)

        // Create one due card (dueAt = now) and one future card.
        let due = try await store.create(question: "Q1", answer: "A1", sourceSpan: nil, now: now)
        _ = try await store.create(question: "Q2", answer: "A2", sourceSpan: nil, now: future)

        let results = try await store.dueCards(asOf: now)

        #expect(results.count == 1)
        #expect(results[0].id == due.id)
    }

    // MARK: apply_updatesFSRSFields_andAppendsReviewLog

    @Test("apply updates FSRS fields on the card and appends a ReviewLog")
    func apply_updatesFSRSFields_andAppendsReviewLog() async throws {
        let container = try makeInMemoryContainer()
        let store = CardStore(container: container)
        let now = Date()
        let engine = LiveFSRS6Engine()

        let snap = try await store.create(question: "Q", answer: "A", sourceSpan: nil, now: now)
        let output = try engine.next(card: snap.schedulingCard, rating: .good, now: now)

        try await store.apply(output, to: snap.id, grade: .good, now: now)

        let updated = try await store.dueCards(asOf: output.card.due)
        let card = try #require(updated.first(where: { $0.id == snap.id }))

        #expect(card.stability == output.card.stability)
        #expect(card.difficulty == output.card.difficulty)
        #expect(card.state == output.card.state)
        #expect(abs(card.dueAt.timeIntervalSince(output.card.due)) < 1)
    }

    // MARK: apply_persistsAcrossStoreReopen

    @Test("apply persists FSRS fields across a store reopen (round-trip)")
    func apply_persistsAcrossStoreReopen() async throws {
        // Use an on-disk store to verify real persistence.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("anghkooey-test-\(UUID()).store")
        defer { try? FileManager.default.removeItem(at: url) }

        let config = ModelConfiguration(url: url)
        // Open at the CURRENT schema (V5) to match the `Card` typealias; pinning
        // an older version crashes the shared PersistentIdentifier registry when
        // co-resident with V5 tests (see feedback_swiftdata_versioned_namespacing).
        let v5Schema = Schema(versionedSchema: AnghkooeySchemaV5.self)
        let container1 = try ModelContainer(for: v5Schema, migrationPlan: AnghkooeyMigrationPlan.self, configurations: config)
        let store1 = CardStore(container: container1)
        let now = Date()
        let engine = LiveFSRS6Engine()

        let snap = try await store1.create(question: "Persist?", answer: "Yes", sourceSpan: nil, now: now)
        let output = try engine.next(card: snap.schedulingCard, rating: .good, now: now)
        try await store1.apply(output, to: snap.id, grade: .good, now: now)

        // Reopen with a fresh container.
        let container2 = try ModelContainer(for: v5Schema, migrationPlan: AnghkooeyMigrationPlan.self, configurations: config)
        let store2 = CardStore(container: container2)

        let cards = try await store2.dueCards(asOf: output.card.due)
        let reloaded = try #require(cards.first(where: { $0.id == snap.id }))

        #expect(reloaded.stability == output.card.stability)
        #expect(reloaded.state == output.card.state)
    }

    // MARK: count_returnsTotalAndDueSeparately

    // MARK: applyPersistsStepMachineFields

    @Test func applyPersistsStepMachineFields() async throws {
        let container = try AnghkooeyModelContainer.makeInMemoryContainer()
        let store = CardStore(container: container)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let snap = try await store.create(
            question: "Q", answer: "A", sourceSpan: nil, now: now
        )

        let updatedCard = SchedulingCard(
            state: .learning,
            stability: 2.0,
            difficulty: 5.0,
            due: now.addingTimeInterval(600),
            reps: 1,
            lapses: 0,
            learningSteps: 1,
            scheduledDays: 0.0,
            elapsedDays: 0.0,
            lastReview: now
        )
        let log = ReviewLogEntry(
            rating: .good,
            stateBefore: .new,
            stabilityBefore: 0,
            difficultyBefore: 0,
            elapsedDays: 0,
            scheduledDays: 0,
            reviewedAt: now
        )
        let output = SchedulerOutput(card: updatedCard, log: log)
        try await store.apply(output, to: snap.id, grade: .good, now: now)

        let due = try await store.dueCards(asOf: now.addingTimeInterval(10_000))
        let persisted = try #require(due.first(where: { $0.id == snap.id }))
        #expect(persisted.reps == 1)
        #expect(persisted.learningSteps == 1)
        #expect(persisted.state == .learning)
    }

    @Test("count returns total card count and due count separately")
    func count_returnsTotalAndDueSeparately() async throws {
        let container = try makeInMemoryContainer()
        let store = CardStore(container: container)
        let now = Date()
        let future = now.addingTimeInterval(7 * 24 * 3600)

        _ = try await store.create(question: "Q1", answer: "A1", sourceSpan: nil, now: now)
        _ = try await store.create(question: "Q2", answer: "A2", sourceSpan: nil, now: now)
        _ = try await store.create(question: "Q3", answer: "A3", sourceSpan: nil, now: future)

        let counts = try await store.count(asOf: now)

        #expect(counts.total == 3)
        #expect(counts.due == 2)
    }
}
