import Testing
import Foundation
@testable import Anghkooey
@testable import AnghkooeyCore

@Suite("Widget grade reconciliation")
@MainActor
struct GradeReconciliationTests {

    private func tmpDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("a queued grade is applied to the store and the queue is cleared")
    func appliesAndClears() async throws {
        let dir = try tmpDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = MockCardStore()
        let card = try await store.create(question: "q", answer: "a", sourceSpan: nil, tags: [], now: .now)
        let bridge = WidgetBridge(containerURL: dir)
        try bridge.appendGrade(WidgetGradeDecision(id: UUID(), cardID: card.id, rating: .good, decidedAt: .now))

        let reconciler = WidgetGradeReconciler(store: store, bridge: bridge)
        try await reconciler.reconcile(now: .now)

        #expect(store.reviewLogs.count == 1)
        #expect(store.reviewLogs[0].cardID == card.id)
        #expect(bridge.readGrades().isEmpty)
    }

    @Test("replaying the same decision id twice applies it only once (idempotent)")
    func idempotentReplay() async throws {
        let dir = try tmpDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = MockCardStore()
        let card = try await store.create(question: "q", answer: "a", sourceSpan: nil, tags: [], now: .now)
        let bridge = WidgetBridge(containerURL: dir)
        let decision = WidgetGradeDecision(id: UUID(), cardID: card.id, rating: .good, decidedAt: .now)
        try bridge.appendGrade(decision)
        try bridge.appendGrade(decision) // duplicate

        let reconciler = WidgetGradeReconciler(store: store, bridge: bridge)
        try await reconciler.reconcile(now: .now)

        #expect(store.reviewLogs.count == 1)
    }

    @Test("a grade for an unknown card is dropped without error")
    func unknownCardDropped() async throws {
        let dir = try tmpDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = MockCardStore()
        let bridge = WidgetBridge(containerURL: dir)
        try bridge.appendGrade(
            WidgetGradeDecision(id: UUID(), cardID: UUID(), rating: .again, decidedAt: .now)
        )
        let reconciler = WidgetGradeReconciler(store: store, bridge: bridge)
        try await reconciler.reconcile(now: .now)
        #expect(store.reviewLogs.isEmpty)
        #expect(bridge.readGrades().isEmpty)
    }
}
