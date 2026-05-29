import Foundation
import SwiftData

/// V2 of the Anghkooey persistence schema.
///
/// Adds the FSRS-6 step-machine fields (`reps`, `lapses`, `learningSteps`,
/// `scheduledDays`, `elapsedDays`) to `Card`. All additions carry safe
/// defaults so V1 → V2 is a lightweight migration (no copy logic needed).
public enum AnghkooeySchemaV2: VersionedSchema {
    public static let versionIdentifier = Schema.Version(2, 0, 0)

    public static var models: [any PersistentModel.Type] {
        // ReviewLog and Tag are unversioned; only list them in V5 (the latest
        // schema) to avoid duplicate-checksum crash in CoreData migration.
        [AnghkooeySchemaV2.Card.self]
    }
}

public extension AnghkooeySchemaV2 {
    /// V2 of the Card model. Adds five FSRS step-machine columns.
    @Model
    public final class Card {
        @Attribute(.unique) public var id: UUID
        public var question: String
        public var answer: String
        public var createdAt: Date
        public var updatedAt: Date
        public var tags: [Tag]
        public var state: CardState
        public var stability: Double
        public var difficulty: Double
        public var dueAt: Date
        public var lastReviewedAt: Date?

        @Relationship(deleteRule: .cascade, inverse: \ReviewLog.card)
        public var reviewLogs: [ReviewLog]

        public var sourceSpan: String?

        // M5.A additions — step-machine state.
        // Stored as Optional so lightweight V1→V2 migration leaves NULL for
        // V1-era rows without triggering Core Data's non-null validation.
        // Callers read through Card.Snapshot (non-optional, defaults via ?? 0).
        public var reps: Int?
        public var lapses: Int?
        public var learningSteps: Int?
        public var scheduledDays: Double?
        public var elapsedDays: Double?

        public init(
            id: UUID = UUID(),
            question: String,
            answer: String,
            createdAt: Date = .now,
            updatedAt: Date = .now,
            tags: [Tag] = [],
            state: CardState = .new,
            stability: Double = 0,
            difficulty: Double = 0,
            dueAt: Date = .now,
            lastReviewedAt: Date? = nil,
            reviewLogs: [ReviewLog] = [],
            sourceSpan: String? = nil,
            reps: Int = 0,
            lapses: Int = 0,
            learningSteps: Int = 0,
            scheduledDays: Double = 0,
            elapsedDays: Double = 0
        ) {
            self.id = id
            self.question = question
            self.answer = answer
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.tags = tags
            self.state = state
            self.stability = stability
            self.difficulty = difficulty
            self.dueAt = dueAt
            self.lastReviewedAt = lastReviewedAt
            self.reviewLogs = reviewLogs
            self.sourceSpan = sourceSpan
            self.reps = reps
            self.lapses = lapses
            self.learningSteps = learningSteps
            self.scheduledDays = scheduledDays
            self.elapsedDays = elapsedDays
        }
    }
}
