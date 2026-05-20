import Foundation
import SwiftData
import Testing
// Selective imports: the package exports an empty `enum AnghkooeyCore` as its
// namespace placeholder (M0 leftover), which shadows the module name when
// qualifying like `AnghkooeyCore.Tag`. Importing the specific symbols here
// also avoids a name collision between our `Tag` model and `Testing.Tag`.
import class AnghkooeyCore.Card
import class AnghkooeyCore.ReviewLog
import class AnghkooeyCore.Tag
import enum AnghkooeyCore.CardState
import enum AnghkooeyCore.Rating
import enum AnghkooeyCore.AnghkooeyModelContainer

// MARK: - In-memory container

@Test
func inMemoryContainer_initializesWithoutThrowing() throws {
    _ = try AnghkooeyModelContainer.makeInMemoryContainer()
}

@Test
func inMemoryContainer_canInsertAndFetchCard() throws {
    let container = try AnghkooeyModelContainer.makeInMemoryContainer()
    let context = ModelContext(container)
    let card = Card(question: "Q?", answer: "A.")
    let id = card.id

    context.insert(card)
    try context.save()

    let descriptor = FetchDescriptor<Card>(predicate: #Predicate { $0.id == id })
    let fetched = try #require(try context.fetch(descriptor).first)
    #expect(fetched.id == id)
    #expect(fetched.question == "Q?")
    #expect(fetched.answer == "A.")
}

// MARK: - Relationships

@Test
func card_tagRelationship_isInverseLinked() throws {
    let container = try AnghkooeyModelContainer.makeInMemoryContainer()
    let context = ModelContext(container)
    let card = Card(question: "Q?", answer: "A.")
    let tag = Tag(name: "swift")
    card.tags.append(tag)

    context.insert(card)
    context.insert(tag)
    try context.save()

    let cardID = card.id
    let cardDescriptor = FetchDescriptor<Card>(predicate: #Predicate { $0.id == cardID })
    let refetchedCard = try #require(try context.fetch(cardDescriptor).first)
    #expect(refetchedCard.tags.contains(where: { $0.normalizedName == "swift" }))

    let tagID = tag.id
    let tagDescriptor = FetchDescriptor<Tag>(predicate: #Predicate { $0.id == tagID })
    let refetchedTag = try #require(try context.fetch(tagDescriptor).first)
    #expect(refetchedTag.cards.contains(where: { $0.id == cardID }))
}

@Test
func card_reviewLogCascadeDelete() throws {
    let container = try AnghkooeyModelContainer.makeInMemoryContainer()
    let context = ModelContext(container)
    let card = Card(question: "Q?", answer: "A.")
    let log = ReviewLog(
        card: card,
        reviewedAt: .now,
        rating: .good,
        stateBefore: .new,
        stabilityBefore: 0,
        difficultyBefore: 0,
        elapsedDays: 0,
        scheduledDays: 1
    )
    card.reviewLogs.append(log)

    context.insert(card)
    context.insert(log)
    try context.save()

    let beforeDelete = try context.fetch(FetchDescriptor<ReviewLog>())
    #expect(beforeDelete.count == 1)

    context.delete(card)
    try context.save()

    let afterDelete = try context.fetch(FetchDescriptor<ReviewLog>())
    #expect(afterDelete.isEmpty)
}

// MARK: - Tag uniqueness

@Test
func tag_uniqueByName_caseInsensitive() throws {
    let container = try AnghkooeyModelContainer.makeInMemoryContainer()
    let context = ModelContext(container)

    context.insert(Tag(name: "swift"))
    try context.save()

    // Inserting a differently-cased duplicate must not produce a second row.
    // Uniqueness is enforced on `normalizedName` (`@Attribute(.unique)`), so
    // SwiftData performs an UPSERT keyed on the normalized form rather than
    // creating a second Tag.
    context.insert(Tag(name: "Swift"))
    try context.save()

    let allTags = try context.fetch(FetchDescriptor<Tag>())
    #expect(allTags.count == 1, "Case-variant tag names must collapse to one row")
    #expect(allTags.first?.normalizedName == "swift")
}

// MARK: - Pinned raw values (schema-drift tripwires)

@Test
func rating_rawValue_matchesFSRSSpec() {
    #expect(Rating.again.rawValue == 1)
    #expect(Rating.hard.rawValue == 2)
    #expect(Rating.good.rawValue == 3)
    #expect(Rating.easy.rawValue == 4)
}

@Test
func cardState_rawValue_isStable() {
    #expect(CardState.new.rawValue == 0)
    #expect(CardState.learning.rawValue == 1)
    #expect(CardState.review.rawValue == 2)
    #expect(CardState.relearning.rawValue == 3)
}
