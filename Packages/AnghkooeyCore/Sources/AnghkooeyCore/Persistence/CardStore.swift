import Foundation
import SwiftData

/// Public alias for the current persisted Card model. Downstream code
/// (UI, AppState, tests) should reference `Card` — never
/// `AnghkooeySchemaVN.Card` directly — so future migrations don't ripple
/// through call sites.
public typealias Card = AnghkooeySchemaV5.Card

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
    struct Snapshot: Sendable, Equatable, Identifiable {
        public let id: UUID
        public let question: String
        public let answer: String
        public let sourceSpan: String?
        public let tags: [String]
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
        public let mnemonic: String?
        public let clozeGroupID: UUID?
        public let clozeBuriedUntil: Date?

        public init(
            id: UUID,
            question: String,
            answer: String,
            sourceSpan: String? = nil,
            tags: [String] = [],
            state: CardState,
            stability: Double,
            difficulty: Double,
            dueAt: Date,
            lastReviewedAt: Date? = nil,
            reps: Int = 0,
            lapses: Int = 0,
            learningSteps: Int = 0,
            scheduledDays: Double = 0,
            elapsedDays: Double = 0,
            mnemonic: String? = nil,
            clozeGroupID: UUID? = nil,
            clozeBuriedUntil: Date? = nil
        ) {
            self.id = id
            self.question = question
            self.answer = answer
            self.sourceSpan = sourceSpan
            self.tags = tags
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
            self.mnemonic = mnemonic
            self.clozeGroupID = clozeGroupID
            self.clozeBuriedUntil = clozeBuriedUntil
        }

        init(from card: Card) {
            self.init(
                id: card.id,
                question: card.question,
                answer: card.answer,
                sourceSpan: card.sourceSpan,
                tags: card.tags.map(\.name).sorted(),
                state: card.state,
                stability: card.stability,
                difficulty: card.difficulty,
                dueAt: card.dueAt,
                lastReviewedAt: card.lastReviewedAt,
                reps: card.reps ?? 0,
                lapses: card.lapses ?? 0,
                learningSteps: card.learningSteps ?? 0,
                scheduledDays: card.scheduledDays ?? 0,
                elapsedDays: card.elapsedDays ?? 0,
                mnemonic: card.mnemonic,
                clozeGroupID: card.clozeGroupID,
                clozeBuriedUntil: card.clozeBuriedUntil
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
    func create(question: String, answer: String, sourceSpan: String?, tags: [String], now: Date) async throws -> Card.Snapshot

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

    /// Shifts every card's `dueAt` forward by `days`. Used by Freeze "I'm away"
    /// to slide the entire deck so the user returns with zero overdue debt.
    ///
    /// - Parameter days: Non-negative integer days to add. Passing 0 is a no-op.
    /// - Throws: `PersistenceError.invalidShift` if `days < 0`.
    func shiftAllDueDates(byDays days: Int) async throws

    /// Returns all cards in the store, sorted by `dueAt`. Used by tests and
    /// the forthcoming Library surface.
    func allCards() async throws -> [Card.Snapshot]

    /// Updates the `question` and `answer` of the card identified by `id`.
    ///
    /// Passing an unknown `id` is a silent no-op.
    /// - Throws: `PersistenceError` on a SwiftData write failure.
    func update(id: UUID, question: String, answer: String, tags: [String]) async throws

    /// Sets the on-device mnemonic for the card identified by `id`.
    ///
    /// Passing an unknown `id` is a silent no-op.
    /// - Throws: `PersistenceError` on a SwiftData write failure.
    func updateMnemonic(id: UUID, mnemonic: String) async throws

    /// Returns the number of cards whose `stability` is at or above `thresholdDays`.
    ///
    /// A card's stability (in days) represents how long FSRS predicts the user
    /// will retain it; reaching the threshold is the project's definition of
    /// long-term memory. The default threshold is `LTMConfig.defaultThresholdDays`.
    func longTermMemoryCount(thresholdDays: Double) async throws -> Int

    /// Returns the first card whose `sourceSpan` equals `span`, or `nil` if none.
    /// Used by the Anki importer to skip cards already in the store.
    func findBySourceSpan(_ span: String) async throws -> Card.Snapshot?

    /// Creates a card with a caller-supplied `dueAt` date.
    /// Used by the Anki importer to preserve Anki scheduling dates.
    func createImported(
        question: String,
        answer: String,
        sourceSpan: String?,
        tags: [String],
        dueAt: Date,
        now: Date
    ) async throws -> Card.Snapshot

    /// Fans a cloze template into one card per deletion, all sharing a fresh
    /// `clozeGroupID`. Each card's `question`/`answer` are pre-rendered.
    func createClozeCards(from template: ClozeTemplate, tags: [String], now: Date) async throws -> [Card.Snapshot]

    /// Returns a narrow projection of every `ReviewLog`, sorted by
    /// `(cardID, reviewedAt)`, for the FSRS optimizer. Projects only the four
    /// fields `OptimizationDataset` needs — never walks full `Card` graphs.
    func optimizationReviewLogs() async throws -> [OptimizationReviewLogRow]
}

// MARK: - CardStoreProtocol backward-compat extensions

public extension CardStoreProtocol {
    /// Creates a card with no tags. Existing call sites compile without change.
    func create(question: String, answer: String, sourceSpan: String?, now: Date) async throws -> Card.Snapshot {
        try await create(question: question, answer: answer, sourceSpan: sourceSpan, tags: [], now: now)
    }

    /// Default implementation that fetches all cards and filters in memory.
    ///
    /// The `CardStore` actor overrides this with a `fetchCount` predicate for
    /// efficiency. Mock and test implementations get this fallback for free.
    func longTermMemoryCount(thresholdDays: Double = LTMConfig.defaultThresholdDays) async throws -> Int {
        let all = try await allCards()
        return LTMConfig.count(all, thresholdDays: thresholdDays)
    }
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

    public func create(question: String, answer: String, sourceSpan: String?, tags: [String], now: Date) async throws -> Card.Snapshot {
        let tagObjects = try findOrCreateTags(tags)
        let card = Card(
            id: UUID(),
            question: question,
            answer: answer,
            createdAt: now,
            updatedAt: now,
            tags: tagObjects,
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

    private func findOrCreateTags(_ names: [String]) throws -> [Tag] {
        var result: [Tag] = []
        for name in names {
            let norm = Tag.normalize(name)
            let predicate = #Predicate<Tag> { $0.normalizedName == norm }
            let descriptor = FetchDescriptor<Tag>(predicate: predicate)
            if let existing = try modelContext.fetch(descriptor).first {
                result.append(existing)
            } else {
                let tag = Tag(name: name)
                modelContext.insert(tag)
                result.append(tag)
            }
        }
        return result
    }

    public func dueCards(asOf now: Date) async throws -> [Card.Snapshot] {
        let distantPast = Date.distantPast
        let predicate = #Predicate<Card> {
            $0.dueAt <= now && ($0.clozeBuriedUntil ?? distantPast) <= now
        }
        let descriptor = FetchDescriptor<Card>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.dueAt), SortDescriptor(\.id)]
        )
        return try modelContext.fetch(descriptor).map { Card.Snapshot(from: $0) }
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
        card.reps = output.card.reps
        card.lapses = output.card.lapses
        card.learningSteps = output.card.learningSteps
        card.scheduledDays = output.card.scheduledDays
        card.elapsedDays = output.card.elapsedDays
        card.updatedAt = now

        if let groupID = card.clozeGroupID {
            let buryUntil = Calendar.current.startOfDay(for: now).addingTimeInterval(86_400)
            let reviewedID = card.id
            let sibPredicate = #Predicate<Card> { $0.clozeGroupID == groupID && $0.id != reviewedID }
            for sib in try modelContext.fetch(FetchDescriptor<Card>(predicate: sibPredicate)) {
                sib.clozeBuriedUntil = buryUntil
            }
        }

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
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    public func count(asOf now: Date) async throws -> (total: Int, due: Int) {
        let allDescriptor = FetchDescriptor<Card>()
        let dueDescriptor = FetchDescriptor<Card>(predicate: #Predicate<Card> { $0.dueAt <= now })
        let total = try modelContext.fetchCount(allDescriptor)
        let due = try modelContext.fetchCount(dueDescriptor)
        return (total: total, due: due)
    }

    public func shiftAllDueDates(byDays days: Int) async throws {
        guard days >= 0 else { throw PersistenceError.invalidShift(days: days) }
        guard days > 0 else { return }
        let interval = TimeInterval(days) * 86_400
        let all = try modelContext.fetch(FetchDescriptor<Card>())
        for card in all {
            card.dueAt = card.dueAt.addingTimeInterval(interval)
        }
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    public func allCards() async throws -> [Card.Snapshot] {
        let descriptor = FetchDescriptor<Card>(sortBy: [SortDescriptor(\.dueAt)])
        return try modelContext.fetch(descriptor).map { Card.Snapshot(from: $0) }
    }

    public func optimizationReviewLogs() async throws -> [OptimizationReviewLogRow] {
        let descriptor = FetchDescriptor<ReviewLog>(sortBy: [SortDescriptor(\.reviewedAt)])
        let logs = try modelContext.fetch(descriptor)
        let rows: [OptimizationReviewLogRow] = logs.compactMap { log in
            guard let cardID = log.card?.id else { return nil }
            return OptimizationReviewLogRow(
                cardID: cardID, reviewedAt: log.reviewedAt,
                rating: log.rating, elapsedDays: log.elapsedDays)
        }
        return rows.sorted {
            $0.cardID == $1.cardID ? $0.reviewedAt < $1.reviewedAt
                                   : $0.cardID.uuidString < $1.cardID.uuidString
        }
    }

    public func update(id: UUID, question: String, answer: String, tags: [String]) async throws {
        let predicate = #Predicate<Card> { $0.id == id }
        let descriptor = FetchDescriptor<Card>(predicate: predicate)
        guard let card = try modelContext.fetch(descriptor).first else { return }
        card.question = question
        card.answer = answer
        card.tags = try findOrCreateTags(tags)
        card.updatedAt = .now
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    public func updateMnemonic(id: UUID, mnemonic: String) async throws {
        let predicate = #Predicate<Card> { $0.id == id }
        let descriptor = FetchDescriptor<Card>(predicate: predicate)
        guard let card = try modelContext.fetch(descriptor).first else { return }
        card.mnemonic = mnemonic
        card.updatedAt = .now
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    public func longTermMemoryCount(thresholdDays: Double) async throws -> Int {
        // Local binding required — #Predicate macro cannot capture a parameter
        // directly; it must reference a local `let` in the enclosing scope.
        let threshold = thresholdDays
        let predicate = #Predicate<Card> { $0.stability >= threshold }
        let descriptor = FetchDescriptor<Card>(predicate: predicate)
        return try modelContext.fetchCount(descriptor)
    }

    public func findBySourceSpan(_ span: String) async throws -> Card.Snapshot? {
        let predicate = #Predicate<Card> { $0.sourceSpan == span }
        let descriptor = FetchDescriptor<Card>(predicate: predicate)
        return try modelContext.fetch(descriptor).first.map { Card.Snapshot(from: $0) }
    }

    public func createImported(
        question: String,
        answer: String,
        sourceSpan: String?,
        tags: [String],
        dueAt: Date,
        now: Date
    ) async throws -> Card.Snapshot {
        let tagObjects = try findOrCreateTags(tags)
        let card = Card(
            id: UUID(),
            question: question,
            answer: answer,
            createdAt: now,
            updatedAt: now,
            tags: tagObjects,
            state: .new,
            stability: 0,
            difficulty: 0,
            dueAt: dueAt,
            lastReviewedAt: nil,
            reviewLogs: [],
            sourceSpan: sourceSpan
        )
        modelContext.insert(card)
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
        return Card.Snapshot(from: card)
    }

    public func createClozeCards(from template: ClozeTemplate, tags: [String], now: Date) async throws -> [Card.Snapshot] {
        let tagObjects = try findOrCreateTags(tags)
        let groupID = UUID()
        var snaps: [Card.Snapshot] = []
        for idx in template.indices {
            let card = Card(
                question: ClozeMarkupParser.renderQuestion(template, index: idx),
                answer: ClozeMarkupParser.renderAnswer(template, index: idx),
                createdAt: now, updatedAt: now, tags: tagObjects,
                dueAt: now,
                cardType: .cloze, clozeGroupID: groupID, clozeIndex: idx,
                clozeSourceText: template.markup
            )
            modelContext.insert(card)
            snaps.append(Card.Snapshot(from: card))
        }
        do { try modelContext.save() } catch { modelContext.rollback(); throw error }
        return snaps
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
    public var updateError: Error?

    public init() {}

    public func create(question: String, answer: String, sourceSpan: String?, tags: [String], now: Date) async throws -> Card.Snapshot {
        if let err = createError { throw err }
        let snap = Card.Snapshot(
            id: UUID(),
            question: question,
            answer: answer,
            sourceSpan: sourceSpan,
            tags: tags,
            state: .new,
            stability: 0,
            difficulty: 0,
            dueAt: now
        )
        cards.append(snap)
        return snap
    }

    public func dueCards(asOf now: Date) async throws -> [Card.Snapshot] {
        cards.filter { $0.dueAt <= now && ($0.clozeBuriedUntil ?? .distantPast) <= now }
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
            tags: old.tags,
            state: output.card.state,
            stability: output.card.stability,
            difficulty: output.card.difficulty,
            dueAt: output.card.due,
            lastReviewedAt: now,
            reps: output.card.reps,
            lapses: output.card.lapses,
            learningSteps: output.card.learningSteps,
            scheduledDays: output.card.scheduledDays,
            elapsedDays: output.card.elapsedDays,
            mnemonic: old.mnemonic,
            clozeGroupID: old.clozeGroupID,
            clozeBuriedUntil: old.clozeBuriedUntil
        )
        // Bury cloze siblings until next day
        if let groupID = old.clozeGroupID {
            let buryUntil = Calendar.current.startOfDay(for: now).addingTimeInterval(86_400)
            cards = cards.map { snap in
                guard snap.clozeGroupID == groupID, snap.id != cardID else { return snap }
                return Card.Snapshot(
                    id: snap.id, question: snap.question, answer: snap.answer,
                    sourceSpan: snap.sourceSpan, tags: snap.tags,
                    state: snap.state, stability: snap.stability, difficulty: snap.difficulty,
                    dueAt: snap.dueAt, lastReviewedAt: snap.lastReviewedAt,
                    reps: snap.reps, lapses: snap.lapses, learningSteps: snap.learningSteps,
                    scheduledDays: snap.scheduledDays, elapsedDays: snap.elapsedDays,
                    mnemonic: snap.mnemonic, clozeGroupID: snap.clozeGroupID,
                    clozeBuriedUntil: buryUntil
                )
            }
        }
    }

    public func count(asOf now: Date) async throws -> (total: Int, due: Int) {
        (total: cards.count, due: cards.filter { $0.dueAt <= now }.count)
    }

    public func shiftAllDueDates(byDays days: Int) async throws {
        guard days >= 0 else { throw PersistenceError.invalidShift(days: days) }
        guard days > 0 else { return }
        let interval = TimeInterval(days) * 86_400
        cards = cards.map { snap in
            Card.Snapshot(
                id: snap.id,
                question: snap.question,
                answer: snap.answer,
                sourceSpan: snap.sourceSpan,
                tags: snap.tags,
                state: snap.state,
                stability: snap.stability,
                difficulty: snap.difficulty,
                dueAt: snap.dueAt.addingTimeInterval(interval),
                lastReviewedAt: snap.lastReviewedAt,
                reps: snap.reps,
                lapses: snap.lapses,
                learningSteps: snap.learningSteps,
                scheduledDays: snap.scheduledDays,
                elapsedDays: snap.elapsedDays,
                mnemonic: snap.mnemonic,
                clozeGroupID: snap.clozeGroupID,
                clozeBuriedUntil: snap.clozeBuriedUntil
            )
        }
    }

    public func allCards() async throws -> [Card.Snapshot] {
        cards.sorted { $0.dueAt < $1.dueAt }
    }

    public func optimizationReviewLogs() async throws -> [OptimizationReviewLogRow] {
        reviewLogs.map { entry in
            OptimizationReviewLogRow(
                cardID: entry.cardID,
                reviewedAt: entry.output.log.reviewedAt,
                rating: entry.grade,
                elapsedDays: entry.output.log.elapsedDays)
        }
        .sorted { $0.cardID == $1.cardID ? $0.reviewedAt < $1.reviewedAt
                                         : $0.cardID.uuidString < $1.cardID.uuidString }
    }

    public func update(id: UUID, question: String, answer: String, tags: [String]) async throws {
        if let err = updateError { throw err }
        guard let idx = cards.firstIndex(where: { $0.id == id }) else { return }
        let old = cards[idx]
        cards[idx] = Card.Snapshot(
            id: old.id,
            question: question,
            answer: answer,
            sourceSpan: old.sourceSpan,
            tags: tags,
            state: old.state,
            stability: old.stability,
            difficulty: old.difficulty,
            dueAt: old.dueAt,
            lastReviewedAt: old.lastReviewedAt,
            reps: old.reps,
            lapses: old.lapses,
            learningSteps: old.learningSteps,
            scheduledDays: old.scheduledDays,
            elapsedDays: old.elapsedDays,
            mnemonic: old.mnemonic,
            clozeGroupID: old.clozeGroupID,
            clozeBuriedUntil: old.clozeBuriedUntil
        )
    }

    public func updateMnemonic(id: UUID, mnemonic: String) async throws {
        guard let idx = cards.firstIndex(where: { $0.id == id }) else { return }
        let old = cards[idx]
        cards[idx] = Card.Snapshot(
            id: old.id,
            question: old.question,
            answer: old.answer,
            sourceSpan: old.sourceSpan,
            tags: old.tags,
            state: old.state,
            stability: old.stability,
            difficulty: old.difficulty,
            dueAt: old.dueAt,
            lastReviewedAt: old.lastReviewedAt,
            reps: old.reps,
            lapses: old.lapses,
            learningSteps: old.learningSteps,
            scheduledDays: old.scheduledDays,
            elapsedDays: old.elapsedDays,
            mnemonic: mnemonic,
            clozeGroupID: old.clozeGroupID,
            clozeBuriedUntil: old.clozeBuriedUntil
        )
    }

    public func findBySourceSpan(_ span: String) async throws -> Card.Snapshot? {
        cards.first { $0.sourceSpan == span }
    }

    public func createImported(
        question: String,
        answer: String,
        sourceSpan: String?,
        tags: [String],
        dueAt: Date,
        now: Date
    ) async throws -> Card.Snapshot {
        if let err = createError { throw err }
        let snap = Card.Snapshot(
            id: UUID(),
            question: question,
            answer: answer,
            sourceSpan: sourceSpan,
            tags: tags,
            state: .new,
            stability: 0,
            difficulty: 0,
            dueAt: dueAt
        )
        cards.append(snap)
        return snap
    }

    public func createClozeCards(from template: ClozeTemplate, tags: [String], now: Date) async throws -> [Card.Snapshot] {
        if let err = createError { throw err }
        let groupID = UUID()
        var snaps: [Card.Snapshot] = []
        for idx in template.indices {
            let snap = Card.Snapshot(
                id: UUID(),
                question: ClozeMarkupParser.renderQuestion(template, index: idx),
                answer: ClozeMarkupParser.renderAnswer(template, index: idx),
                tags: tags,
                state: .new,
                stability: 0,
                difficulty: 0,
                dueAt: now,
                clozeGroupID: groupID
            )
            snaps.append(snap)
            cards.append(snap)
        }
        return snaps
    }
}
