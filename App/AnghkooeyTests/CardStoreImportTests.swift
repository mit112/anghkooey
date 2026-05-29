import Testing
import Foundation
@testable import AnghkooeyCore

@Suite("CardStore import methods")
@MainActor
struct CardStoreImportTests {

    @Test func findBySourceSpan_returnsNil_whenNotFound() async throws {
        let store = MockCardStore()
        let result = try await store.findBySourceSpan("anki:9999")
        #expect(result == nil)
    }

    @Test func findBySourceSpan_returnsSnapshot_whenFound() async throws {
        let store = MockCardStore()
        _ = try await store.createImported(
            question: "Q", answer: "A",
            sourceSpan: "anki:1001", tags: [],
            dueAt: Date(timeIntervalSince1970: 1_700_000_000),
            now: .now
        )
        let result = try await store.findBySourceSpan("anki:1001")
        #expect(result?.sourceSpan == "anki:1001")
    }

    @Test func createImported_preservesDueAt() async throws {
        let store = MockCardStore()
        let expectedDue = Date(timeIntervalSince1970: 1_750_000_000)
        let snap = try await store.createImported(
            question: "Q", answer: "A",
            sourceSpan: "anki:42", tags: ["Biology"],
            dueAt: expectedDue, now: .now
        )
        #expect(snap.dueAt == expectedDue)
        #expect(snap.sourceSpan == "anki:42")
        #expect(snap.tags == ["Biology"])
    }

    @Test func createImported_stateIsNew() async throws {
        let store = MockCardStore()
        let snap = try await store.createImported(
            question: "Q", answer: "A",
            sourceSpan: nil, tags: [],
            dueAt: .now, now: .now
        )
        #expect(snap.state == .new)
    }
}
