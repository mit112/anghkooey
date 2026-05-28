import Testing
import Foundation
@testable import AnghkooeyCore

@Suite("Widget bridge file contract")
struct WidgetBridgeTests {

    private func tmpDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("snapshot round-trips through the bridge")
    func snapshotRoundTrip() throws {
        let dir = try tmpDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let bridge = WidgetBridge(containerURL: dir)
        let snap = WidgetDueSnapshot(
            cardID: UUID(),
            question: "What is the capital of France?",
            dueCount: 7
        )
        try bridge.writeSnapshot(snap)
        let loaded = bridge.readSnapshot()
        #expect(loaded == snap)
    }

    @Test("reading a missing snapshot returns nil")
    func missingSnapshotNil() throws {
        let dir = try tmpDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let bridge = WidgetBridge(containerURL: dir)
        #expect(bridge.readSnapshot() == nil)
    }

    @Test("appended grade decisions are readable in order")
    func gradeAppendReadOrder() throws {
        let dir = try tmpDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let bridge = WidgetBridge(containerURL: dir)
        let c1 = UUID(); let c2 = UUID()
        try bridge.appendGrade(WidgetGradeDecision(id: UUID(), cardID: c1, rating: .again, decidedAt: Date(timeIntervalSinceReferenceDate: 1)))
        try bridge.appendGrade(WidgetGradeDecision(id: UUID(), cardID: c2, rating: .good, decidedAt: Date(timeIntervalSinceReferenceDate: 2)))
        let decisions = bridge.readGrades()
        #expect(decisions.count == 2)
        #expect(decisions[0].cardID == c1)
        #expect(decisions[1].cardID == c2)
    }

    @Test("clearing grades removes the queue file")
    func clearGrades() throws {
        let dir = try tmpDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let bridge = WidgetBridge(containerURL: dir)
        try bridge.appendGrade(WidgetGradeDecision(id: UUID(), cardID: UUID(), rating: .good, decidedAt: .now))
        try bridge.clearGrades()
        #expect(bridge.readGrades().isEmpty)
    }
}
