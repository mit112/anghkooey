import Foundation
import SwiftData

public enum AnghkooeySchemaV4: VersionedSchema {
    public static let versionIdentifier = Schema.Version(4, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [AnghkooeySchemaV4.Card.self]
    }
}

public extension AnghkooeySchemaV4 {
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

        // V4: sourceSpan promoted to card-level field (was present in V3, V4 is migration anchor for import)
        public var sourceSpan: String?

        public var reps: Int?
        public var lapses: Int?
        public var learningSteps: Int?
        public var scheduledDays: Double?
        public var elapsedDays: Double?
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
