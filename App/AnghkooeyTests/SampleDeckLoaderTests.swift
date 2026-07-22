import Testing
import Foundation
@testable import Anghkooey
import AnghkooeyCore

@MainActor @Suite struct SampleDeckLoaderTests {
    @Test func loadsBundledDeckIntoStore() async throws {
        let store = MockCardStore()
        // Inject JSON data directly to avoid bundle dependency in tests
        let json = """
        [
          {"question": "Q1", "answer": "A1", "tags": ["Spanish"]},
          {"question": "Q2", "answer": "A2", "tags": ["Math"]},
          {"question": "Q3", "answer": "A3", "tags": ["Biology"]},
          {"question": "Q4", "answer": "A4", "tags": ["Trivia"]},
          {"question": "Q5", "answer": "A5", "tags": ["Geography"]},
          {"question": "Q6", "answer": "A6", "tags": ["Spanish"]},
          {"question": "Q7", "answer": "A7", "tags": ["Literature"]},
          {"question": "Q8", "answer": "A8", "tags": ["Math"]},
          {"question": "Q9", "answer": "A9", "tags": ["Trivia"]},
          {"question": "Q10", "answer": "A10", "tags": ["Anghkooey 101"]}
        ]
        """.data(using: .utf8)!
        let loader = SampleDeckLoader(store: store, jsonData: json)
        let count = try await loader.load(now: .now)
        #expect(count >= 10)
        let all = try await store.allCards()
        #expect(all.count == count)
        #expect(all.contains { $0.tags.contains("Spanish") })
    }

    /// Loading twice must not double-insert: the second call inserts nothing and
    /// the store holds exactly one copy of the deck (#46).
    @Test func loadIsIdempotent() async throws {
        let store = MockCardStore()
        let json = """
        [
          {"question": "Q1", "answer": "A1", "tags": ["Spanish"]},
          {"question": "Q2", "answer": "A2", "tags": ["Math"]}
        ]
        """.data(using: .utf8)!
        let loader = SampleDeckLoader(store: store, jsonData: json)
        let first = try await loader.load(now: .now)
        let second = try await loader.load(now: .now)
        #expect(first == 2)
        #expect(second == 0)
        let all = try await store.allCards()
        #expect(all.count == 2)
    }
}
