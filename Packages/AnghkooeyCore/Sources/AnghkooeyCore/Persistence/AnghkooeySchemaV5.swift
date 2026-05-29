import Foundation
import SwiftData

public enum AnghkooeySchemaV5: VersionedSchema {
    public static let versionIdentifier = Schema.Version(5, 0, 0)
    public static var models: [any PersistentModel.Type] {
        [AnghkooeySchemaV5.Card.self, ReviewLog.self, Tag.self]
    }
}

public extension AnghkooeySchemaV5 {
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
        public var reps: Int?
        public var lapses: Int?
        public var learningSteps: Int?
        public var scheduledDays: Double?
        public var elapsedDays: Double?
        public var mnemonic: String?

        // V5: cloze metadata. All Optional for lightweight migration.
        public var cardType: CardType?
        public var clozeGroupID: UUID?
        public var clozeIndex: Int?
        public var clozeSourceText: String?
        public var clozeBuriedUntil: Date?

        public init(
            id: UUID = UUID(), question: String, answer: String,
            createdAt: Date = .now, updatedAt: Date = .now, tags: [Tag] = [],
            state: CardState = .new, stability: Double = 0, difficulty: Double = 0,
            dueAt: Date = .now, lastReviewedAt: Date? = nil, reviewLogs: [ReviewLog] = [],
            sourceSpan: String? = nil, reps: Int = 0, lapses: Int = 0,
            learningSteps: Int = 0, scheduledDays: Double = 0, elapsedDays: Double = 0,
            mnemonic: String? = nil,
            cardType: CardType? = nil, clozeGroupID: UUID? = nil, clozeIndex: Int? = nil,
            clozeSourceText: String? = nil, clozeBuriedUntil: Date? = nil
        ) {
            self.id = id; self.question = question; self.answer = answer
            self.createdAt = createdAt; self.updatedAt = updatedAt; self.tags = tags
            self.state = state; self.stability = stability; self.difficulty = difficulty
            self.dueAt = dueAt; self.lastReviewedAt = lastReviewedAt; self.reviewLogs = reviewLogs
            self.sourceSpan = sourceSpan; self.reps = reps; self.lapses = lapses
            self.learningSteps = learningSteps; self.scheduledDays = scheduledDays
            self.elapsedDays = elapsedDays; self.mnemonic = mnemonic
            self.cardType = cardType; self.clozeGroupID = clozeGroupID
            self.clozeIndex = clozeIndex; self.clozeSourceText = clozeSourceText
            self.clozeBuriedUntil = clozeBuriedUntil
        }
    }
}
