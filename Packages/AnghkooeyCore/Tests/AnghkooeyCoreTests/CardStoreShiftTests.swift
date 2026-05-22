import Testing
import Foundation
@testable import AnghkooeyCore

@Suite("CardStore — shiftAllDueDates")
struct CardStoreShiftTests {

    @Test("shifts all cards forward by N days")
    func shiftsAllCards() async throws {
        let store = MockCardStore()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        try await store.create(question: "q1", answer: "a1", sourceSpan: nil, now: now)
        try await store.create(question: "q2", answer: "a2", sourceSpan: nil, now: now)

        let before = try await store.allCards()
        let originalDues = before.map(\.dueAt)

        try await store.shiftAllDueDates(byDays: 5)

        let after = try await store.allCards()
        let expected = originalDues.map { $0.addingTimeInterval(5 * 86_400) }
        #expect(Set(after.map(\.dueAt)) == Set(expected))
    }

    @Test("shift by 0 is a no-op")
    func shiftByZero_noOp() async throws {
        let store = MockCardStore()
        try await store.create(question: "q", answer: "a", sourceSpan: nil, now: .now)
        let before = try await store.allCards()
        try await store.shiftAllDueDates(byDays: 0)
        let after = try await store.allCards()
        #expect(after.map(\.dueAt) == before.map(\.dueAt))
    }

    @Test("negative shift not permitted")
    func negativeShift_throws() async {
        let store = MockCardStore()
        try? await store.create(question: "q", answer: "a", sourceSpan: nil, now: .now)
        await #expect(throws: PersistenceError.self) {
            try await store.shiftAllDueDates(byDays: -1)
        }
    }
}
