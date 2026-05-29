import Foundation
import SwiftData

/// V3 of the Anghkooey persistence schema.
///
/// Adds the `mnemonic` field to `Card`. All additions carry safe defaults
/// (Optional) so V2 → V3 is a lightweight migration — no copy logic needed.
public enum AnghkooeySchemaV3: VersionedSchema {
    public static let versionIdentifier = Schema.Version(3, 0, 0)

    public static var models: [any PersistentModel.Type] {
        // ReviewLog and Tag are unversioned; only list them in V5 (the latest
        // schema) to avoid duplicate-checksum crash in CoreData migration.
        [AnghkooeySchemaV3.Card.self]
    }
}

public extension AnghkooeySchemaV3 {
    /// V3 of the Card model. Adds the `mnemonic` column.
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

        // V2 step-machine fields — Optional for lightweight V1→V2 migration
        public var reps: Int?
        public var lapses: Int?
        public var learningSteps: Int?
        public var scheduledDays: Double?
        public var elapsedDays: Double?

        // V3 mnemonic — Optional so V2-era rows get NULL (not a validation error)
        public var mnemonic: String?

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
            elapsedDays: Double = 0,
            mnemonic: String? = nil
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
            self.mnemonic = mnemonic
        }
    }
}
