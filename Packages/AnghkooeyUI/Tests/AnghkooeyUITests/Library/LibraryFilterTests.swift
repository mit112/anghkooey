import Testing
import Foundation
import AnghkooeyCore
@testable import AnghkooeyUI

@Suite("LibraryView.filter")
struct LibraryFilterTests {

    private func snapshot(
        question: String,
        answer: String,
        tags: [String] = []
    ) -> Card.Snapshot {
        Card.Snapshot(
            id: UUID(),
            question: question,
            answer: answer,
            tags: tags,
            state: .review,
            stability: 5,
            difficulty: 5,
            dueAt: Date(timeIntervalSinceReferenceDate: 0)
        )
    }

    @Test("empty query and nil tag returns all cards")
    func noFilterReturnsAll() {
        let cards = [
            snapshot(question: "What is Swift?", answer: "A language", tags: ["ios"]),
            snapshot(question: "What is a monad?", answer: "A burrito", tags: ["fp"]),
        ]
        let result = LibraryView.filter(cards, searchText: "", selectedTag: nil)
        #expect(result == cards)
    }

    @Test("filters by question substring, case-insensitive")
    func filtersByQuestion() {
        let match = snapshot(question: "What is Swift?", answer: "A language")
        let noMatch = snapshot(question: "What is a monad?", answer: "A burrito")
        let cards = [match, noMatch]
        let result = LibraryView.filter(cards, searchText: "swift", selectedTag: nil)
        #expect(result == [match])
    }

    @Test("filters by answer substring, case-insensitive")
    func filtersByAnswer() {
        let match = snapshot(question: "Q1", answer: "A concurrency primitive")
        let noMatch = snapshot(question: "Q2", answer: "A burrito")
        let cards = [match, noMatch]
        let result = LibraryView.filter(cards, searchText: "CONCURRENCY", selectedTag: nil)
        #expect(result == [match])
    }

    @Test("filters by tag substring, case-insensitive")
    func filtersByTag() {
        let match = snapshot(question: "Q1", answer: "A1", tags: ["SwiftUI"])
        let noMatch = snapshot(question: "Q2", answer: "A2", tags: ["backend"])
        let cards = [match, noMatch]
        let result = LibraryView.filter(cards, searchText: "swiftui", selectedTag: nil)
        #expect(result == [match])
    }

    @Test("composes AND with selectedTag — query and tag both must match")
    func composesWithSelectedTag() {
        let both = snapshot(question: "Swift concurrency", answer: "async/await", tags: ["ios"])
        let tagOnlyNoQuery = snapshot(question: "Kotlin coroutines", answer: "suspend fun", tags: ["ios"])
        let queryOnlyWrongTag = snapshot(question: "Swift concurrency", answer: "async/await", tags: ["backend"])
        let cards = [both, tagOnlyNoQuery, queryOnlyWrongTag]
        let result = LibraryView.filter(cards, searchText: "swift", selectedTag: "ios")
        #expect(result == [both])
    }

    @Test("query matching nothing returns empty")
    func queryMatchingNothingReturnsEmpty() {
        let cards = [
            snapshot(question: "What is Swift?", answer: "A language", tags: ["ios"]),
            snapshot(question: "What is a monad?", answer: "A burrito", tags: ["fp"]),
        ]
        let result = LibraryView.filter(cards, searchText: "nonexistentxyz", selectedTag: nil)
        #expect(result.isEmpty)
    }
}
