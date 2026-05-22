import Foundation
import SwiftData

/// Public alias for the current persisted Card model. Downstream code
/// (UI, AppState, tests) should reference `Card` — never
/// `AnghkooeySchemaVN.Card` directly — so future migrations don't ripple
/// through call sites.
public typealias Card = AnghkooeySchemaV2.Card

// MARK: - Card.Snapshot

public extension Card {
    /// A `Sendable` value-type projection of a persisted `Card`.
    ///
    /// `@Model` classes are not `Sendable`; this struct shuttles card state
    /// across the `CardStore` actor boundary so callers never hold a reference
    /// to a live SwiftData object outside the actor's ModelContext.
    ///
    /// As of M5.A all FSRS fields including step-machine state are persisted
    /// and round-trip through this snapshot.
    struct Snapshot: Sendable, Equatable {
        public let id: UUID
        public let question: String
        public let answer: String
        public let sourceSpan: String?
        public let state: CardState
        public let stability: Double
        public let difficulty: Double
        public let dueAt: Date
        public let lastReviewedAt: Date?
        public let reps: Int
        public let lapses: Int
        public let learningSteps: Int
        public let scheduledDays: Double
        public let elapsedDays: Double

        public init(
            id: UUID,
            question: String,
            answer: String,
            sourceSpan: String? = nil,
            state: CardState,
            stability: Double,
            difficulty: Double,
            dueAt: Date,
            lastReviewedAt: Date? = nil,
            reps: Int = 0,
            lapses: Int = 0,
            learningSteps: Int = 0,
            scheduledDays: Double = 0,
            elapsedDays: Double = 0
        ) {
            self.id = id
            self.question = question
            self.answer = answer
            self.sourceSpan = sourceSpan
            self.state = state
            self.stability = stability
            self.difficulty = difficulty
            self.dueAt = dueAt
            self.lastReviewedAt = lastReviewedAt
            self.reps = reps
            self.lapses = lapses
            self.learningSteps = learningSteps
            self.scheduledDays = scheduledDays
            self.elapsedDays = elapsedDays
        }

        init(from card: Card) {
            self.init(
                id: card.id,
                question: card.question,
                answer: card.answer,
                sourceSpan: card.sourceSpan,
                state: card.state,
                stability: card.stability,
                difficulty: card.difficulty,
                dueAt: card.dueAt,
                lastReviewedAt: card.lastReviewedAt,
                reps: card.reps ?? 0,
                lapses: card.lapses ?? 0,
                learningSteps: card.learningSteps ?? 0,
                scheduledDays: card.scheduledDays ?? 0,
                elapsedDays: card.elapsedDays ?? 0
            )
        }

        /// Reconstructs a `SchedulingCard` suitable for passing to `FSRS6Engine`.
        ///
        /// All step-machine fields are persisted (M5.A) so the scheduler
        /// receives the real position on every call rather than a zeroed proxy.
        public var schedulingCard: SchedulingCard {
            SchedulingCard(
                state: state,
                stability: stability,
                difficulty: difficulty,
                due: dueAt,
                reps: reps,
                lapses: lapses,
                learningSteps: learningSteps,
                scheduledDays: scheduledDays,
                elapsedDays: elapsedDays,
                lastReview: lastReviewedAt
            )
        }
    }
}

// MARK: - CardStoreProtocol

/// Contract for the persistence layer that owns `Card` and `ReviewLog` models.
///
/// All methods are `async` so the concrete actor can schedule work without
/// blocking the caller. The protocol is `Sendable` so it can be stored on
/// `@MainActor` types.
///
/// Callers work with `Card.Snapshot` values — they never receive live `Card`
/// references, keeping SwiftData objects inside the actor.
public protocol CardStoreProtocol: Sendable {

    /// Creates a new `Card` with FSRS initial state (`state: .new`, `dueAt: now`).
    ///
    /// - Parameters:
    ///   - question: The recall prompt.
    ///   - answer: The expected answer.
    ///   - sourceSpan: Optional excerpt from the source material.
    ///   - now: Creation timestamp; also used as `dueAt` so the card is
    ///     immediately due on creation.
    /// - Returns: A snapshot of the persisted card.
    func create(question: String, answer: String, sourceSpan: String?, now: Date) async throws -> Card.Snapshot

    /// Returns snapshots of all cards whose `dueAt ≤ now`.
    func dueCards(asOf now: Date) async throws -> [Card.Snapshot]

    /// Applies a scheduler output to the card identified by `cardID`.
    ///
    /// Updates the card's FSRS fields (`stability`, `difficulty`, `dueAt`,
    /// `lastReviewedAt`, `state`) from `output.card` and appends a `ReviewLog`
    /// entry. Persists atomically via a single `modelContext.save()`.
    ///
    /// - Parameters:
    ///   - output: Result from `FSRS6Engine.next(card:rating:now:)`.
    ///   - cardID: Stable identifier of the card to update.
    ///   - grade: User-facing grade (stored on `ReviewLog`; the FSRS `Rating`
    ///     is in `output.log.rating`).
    ///   - now: Wall-clock instant of the review.
    func apply(_ output: SchedulerOutput, to cardID: UUID, grade: Rating, now: Date) async throws

    /// Returns the total card count and the count of cards due as of `now`.
    func count(asOf now: Date) async throws -> (total: Int, due: Int)
}

// MARK: - CardStore (actor skeleton)

/// Actor-isolated persistence layer wrapping a SwiftData `ModelContainer`.
///
/// All SwiftData access happens on the actor's serial executor, satisfying
/// `ModelContext`'s single-thread requirement without any `@MainActor` coupling.
/// The app target creates one `CardStore` instance and injects it where needed.
public actor CardStore: CardStoreProtocol {

    private let modelContext: ModelContext

    public init(container: ModelContainer) {
        self.modelContext = ModelContext(container)
    }

    public func create(question: String, answer: String, sourceSpan: String?, now: Date) async throws -> Card.Snapshot {
        let card = Card(
            id: UUID(),
            question: question,
            answer: answer,
            createdAt: now,
            updatedAt: now,
            tags: [],
            state: .new,
            stability: 0,
            difficulty: 0,
            dueAt: now,
            lastReviewedAt: nil,
            reviewLogs: [],
            sourceSpan: sourceSpan
        )
        modelContext.insert(card)
        try modelContext.save()
        return Card.Snapshot(from: card)
    }

    public func dueCards(asOf now: Date) async throws -> [Card.Snapshot] {
        let predicate = #Predicate<Card> { $0.dueAt <= now }
        let descriptor = FetchDescriptor<Card>(predicate: predicate)
        let cards = try modelContext.fetch(descriptor)
        return cards.map { Card.Snapshot(from: $0) }
    }

    public func apply(_ output: SchedulerOutput, to cardID: UUID, grade: Rating, now: Date) async throws {
        let id = cardID
        let predicate = #Predicate<Card> { $0.id == id }
        let descriptor = FetchDescriptor<Card>(predicate: predicate)
        guard let card = try modelContext.fetch(descriptor).first else { return }

        card.state = output.card.state
        card.stability = output.card.stability
        card.difficulty = output.card.difficulty
        card.dueAt = output.card.due
        card.lastReviewedAt = now
        card.updatedAt = now

        let log = ReviewLog(
            id: UUID(),
            card: card,
            reviewedAt: now,
            rating: output.log.rating,
            stateBefore: output.log.stateBefore,
            stabilityBefore: output.log.stabilityBefore,
            difficultyBefore: output.log.difficultyBefore,
            elapsedDays: output.log.elapsedDays,
            scheduledDays: output.log.scheduledDays
        )
        modelContext.insert(log)
        try modelContext.save()
    }

    public func count(asOf now: Date) async throws -> (total: Int, due: Int) {
        let allDescriptor = FetchDescriptor<Card>()
        let dueDescriptor = FetchDescriptor<Card>(predicate: #Predicate<Card> { $0.dueAt <= now })
        let total = try modelContext.fetchCount(allDescriptor)
        let due = try modelContext.fetchCount(dueDescriptor)
        return (total: total, due: due)
    }
}

// MARK: - MockCardStore

/// Deterministic in-memory stub of `CardStoreProtocol` for use in tests and
/// SwiftUI previews. Not thread-safe; intended for `@MainActor` test contexts.
public final class MockCardStore: CardStoreProtocol, @unchecked Sendable {

    public private(set) var cards: [Card.Snapshot] = []
    public private(set) var reviewLogs: [(cardID: UUID, output: SchedulerOutput, grade: Rating)] = []
    public var createError: Error?
    public var applyError: Error?

    public init() {}

    public func create(question: String, answer: String, sourceSpan: String?, now: Date) async throws -> Card.Snapshot {
        if let err = createError { throw err }
        let snap = Card.Snapshot(
            id: UUID(),
            question: question,
            answer: answer,
            sourceSpan: sourceSpan,
            state: .new,
            stability: 0,
            difficulty: 0,
            dueAt: now
        )
        cards.append(snap)
        return snap
    }

    public func dueCards(asOf now: Date) async throws -> [Card.Snapshot] {
        cards.filter { $0.dueAt <= now }
    }

    public func apply(_ output: SchedulerOutput, to cardID: UUID, grade: Rating, now: Date) async throws {
        if let err = applyError { throw err }
        reviewLogs.append((cardID: cardID, output: output, grade: grade))
        guard let idx = cards.firstIndex(where: { $0.id == cardID }) else { return }
        let old = cards[idx]
        cards[idx] = Card.Snapshot(
            id: old.id,
            question: old.question,
            answer: old.answer,
            sourceSpan: old.sourceSpan,
            state: output.card.state,
            stability: output.card.stability,
            difficulty: output.card.difficulty,
            dueAt: output.card.due,
            lastReviewedAt: now
        )
    }

    public func count(asOf now: Date) async throws -> (total: Int, due: Int) {
        (total: cards.count, due: cards.filter { $0.dueAt <= now }.count)
    }
}
