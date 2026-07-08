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

    @Test("many sequential appends all survive and read back in order (O_APPEND, no clobber)")
    func manyAppendsAllSurvive() throws {
        let dir = try tmpDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let bridge = WidgetBridge(containerURL: dir)
        let ids = (0..<20).map { _ in UUID() }
        for (i, id) in ids.enumerated() {
            try bridge.appendGrade(WidgetGradeDecision(
                id: UUID(), cardID: id, rating: i.isMultiple(of: 2) ? .again : .good,
                decidedAt: Date(timeIntervalSinceReferenceDate: TimeInterval(i))))
        }
        let read = bridge.readGrades()
        #expect(read.count == 20)
        #expect(read.map(\.cardID) == ids) // every line intact, in append order
    }

    @Test("clearing grades removes the queue file")
    func clearGrades() throws {
        let dir = try tmpDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let bridge = WidgetBridge(containerURL: dir)
        try bridge.appendGrade(WidgetGradeDecision(id: UUID(), cardID: UUID(), rating: .good, decidedAt: .now))
        try bridge.clearGrades()
        #expect(bridge.readGrades().isEmpty)
    }

    // MARK: - Issue #35/#36: answer/revealed/queue schema

    @Test("snapshot round-trips through the bridge with answer, revealed, and queue")
    func snapshotRoundTripWithNewFields() throws {
        let dir = try tmpDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let bridge = WidgetBridge(containerURL: dir)
        let queue = [
            WidgetCardRef(cardID: UUID(), question: "Q2", answer: "A2"),
            WidgetCardRef(cardID: UUID(), question: "Q3", answer: "A3")
        ]
        let snap = WidgetDueSnapshot(
            cardID: UUID(),
            question: "What is the capital of France?",
            dueCount: 7,
            answer: "Paris",
            revealed: true,
            queue: queue
        )
        try bridge.writeSnapshot(snap)
        let loaded = bridge.readSnapshot()
        #expect(loaded == snap)
    }

    @Test("an old-format snapshot (no answer/revealed/queue keys) still decodes with the new fields nil")
    func oldFormatSnapshotStillDecodes() throws {
        let id = UUID()
        let json = """
        {"cardID":"\(id.uuidString)","question":"Old format?","dueCount":2}
        """
        let snap = try JSONDecoder().decode(WidgetDueSnapshot.self, from: Data(json.utf8))
        #expect(snap.cardID == id)
        #expect(snap.question == "Old format?")
        #expect(snap.dueCount == 2)
        #expect(snap.answer == nil)
        #expect(snap.revealed == nil)
        #expect(snap.queue == nil)
    }

    @Test("a corrupt element inside queue degrades to pruning that element, not failing the whole decode")
    func corruptQueueElementDegradesGracefully() throws {
        let currentID = UUID()
        let goodID = UUID()
        let json = """
        {
          "cardID": "\(currentID.uuidString)",
          "question": "Still readable?",
          "dueCount": 3,
          "answer": "Yes",
          "revealed": false,
          "queue": [
            {"cardID": "\(goodID.uuidString)", "question": "Good", "answer": "Fine"},
            {"cardID": "not-a-uuid", "question": "Bad", "answer": "Broken"}
          ]
        }
        """
        let snap = try JSONDecoder().decode(WidgetDueSnapshot.self, from: Data(json.utf8))
        // Current card is intact even though one queue element was corrupt.
        #expect(snap.cardID == currentID)
        #expect(snap.question == "Still readable?")
        #expect(snap.answer == "Yes")
        #expect(snap.revealed == false)
        let queue = try #require(snap.queue)
        #expect(queue.count == 1)
        #expect(queue[0].cardID == goodID)
    }

    @Test("a queue field of the wrong shape entirely degrades to nil rather than failing decode")
    func malformedQueueShapeDegradesToNil() throws {
        let id = UUID()
        let json = """
        {"cardID":"\(id.uuidString)","question":"Q","dueCount":1,"queue":"not-an-array"}
        """
        let snap = try JSONDecoder().decode(WidgetDueSnapshot.self, from: Data(json.utf8))
        #expect(snap.cardID == id)
        #expect(snap.queue == nil)
    }

    // MARK: - Issue #35/#36: local advance/reveal guardrails

    @Test("advancing pops the next queued card, decrements dueCount, and resets revealed")
    func advancingPopsQueue() {
        let currentID = UUID()
        let nextID = UUID()
        let tailID = UUID()
        let current = WidgetDueSnapshot(
            cardID: currentID, question: "Q1", dueCount: 3, answer: "A1", revealed: true,
            queue: [
                WidgetCardRef(cardID: nextID, question: "Q2", answer: "A2"),
                WidgetCardRef(cardID: tailID, question: "Q3", answer: "A3")
            ]
        )
        guard case .advanced(let next) = WidgetDueSnapshot.advancing(from: current, gradedCardID: currentID) else {
            Issue.record("expected .advanced")
            return
        }
        #expect(next.cardID == nextID)
        #expect(next.question == "Q2")
        #expect(next.answer == "A2")
        #expect(next.revealed == false)
        #expect(next.dueCount == 2)
        #expect(next.queue?.map(\.cardID) == [tailID])
    }

    @Test("advancing on a stale/duplicate tap (cardID mismatch) is a no-op")
    func advancingStaleTap() {
        let current = WidgetDueSnapshot(cardID: UUID(), question: "Q1", dueCount: 3)
        #expect(WidgetDueSnapshot.advancing(from: current, gradedCardID: UUID()) == .staleTap)
    }

    @Test("advancing on a nil snapshot is a stale-tap no-op")
    func advancingNilSnapshotIsStaleTap() {
        #expect(WidgetDueSnapshot.advancing(from: nil, gradedCardID: UUID()) == .staleTap)
    }

    @Test("advancing with an exhausted queue and dueCount == 0 reports all caught up")
    func advancingExhaustedQueueAllCaughtUp() {
        let currentID = UUID()
        let current = WidgetDueSnapshot(cardID: currentID, question: "Q1", dueCount: 1, queue: [])
        #expect(WidgetDueSnapshot.advancing(from: current, gradedCardID: currentID) == .allCaughtUp)
    }

    @Test("advancing with an exhausted queue but dueCount > 0 reports the open-app-to-continue sentinel")
    func advancingExhaustedQueueNeedsAppToContinue() {
        let currentID = UUID()
        let current = WidgetDueSnapshot(cardID: currentID, question: "Q1", dueCount: 4, queue: [])
        guard case .advanced(let next) = WidgetDueSnapshot.advancing(from: current, gradedCardID: currentID) else {
            Issue.record("expected .advanced")
            return
        }
        #expect(next.needsAppToContinue)
        #expect(next.dueCount == 3)
    }

    @Test("revealing marks the matching current card revealed")
    func revealingMarksCurrentCard() {
        let id = UUID()
        let current = WidgetDueSnapshot(cardID: id, question: "Q", dueCount: 2, answer: "A", revealed: false)
        let revealed = WidgetDueSnapshot.revealing(current: current, cardID: id)
        #expect(revealed?.revealed == true)
        #expect(revealed?.answer == "A")
        #expect(revealed?.cardID == id)
    }

    @Test("revealing on a stale/duplicate tap (cardID mismatch) is a no-op")
    func revealingStaleTap() {
        let current = WidgetDueSnapshot(cardID: UUID(), question: "Q", dueCount: 2)
        #expect(WidgetDueSnapshot.revealing(current: current, cardID: UUID()) == nil)
    }

    @Test("revealing on a nil snapshot is a no-op")
    func revealingNilSnapshot() {
        #expect(WidgetDueSnapshot.revealing(current: nil, cardID: UUID()) == nil)
    }
}
