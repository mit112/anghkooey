import Testing
import Foundation
@testable import Anghkooey
import AnghkooeyCore
import AnghkooeyUI

// NOTE: The app-host test target cannot use a live CardStore + ModelContainer because
// SwiftData registers @Model types under the module that links them first, causing a
// PersistentIdentifier type-name mismatch when AnghkooeyCore's models are cast in the
// app-host process. (See memory: feedback_swiftdata_versioned_namespacing.md)
//
// Instead this test uses MockCardStore for the ReviewSession wiring and separately
// benchmarks LiveFSRS6Engine.next() — the dominant CPU cost in the review-tap path.
// The ModelContext.save cost (the I/O leg) is measured in the Core package's
// EndToEndReviewFlowTests which runs in the correct module context.

@Suite("ReviewTap latency — M6 PERFORMANCE.md baseline")
@MainActor
struct ReviewTapLatencyTests {

    /// Measures the two CPU-bound legs of ReviewSession.submit():
    ///   1. LiveFSRS6Engine.next()  — FSRS-6 scheduling math
    ///   2. ReviewSession.submit()  — full state-machine path through MockCardStore
    ///
    /// MockCardStore.apply() is an in-memory dictionary mutation (~µs), which is
    /// a lower bound on the real ModelContext.save path. The FSRS math is identical
    /// in both paths and is the dominant latency on device.
    @Test("review-tap: measure 20 submit() calls via MockCardStore + LiveFSRS6Engine")
    func reviewTap_measuredWithMockStore() async throws {
        let store = MockCardStore()
        let engine = LiveFSRS6Engine()
        let seedDate = Date(timeIntervalSinceReferenceDate: 0)

        // Seed 20 cards all due at seedDate
        for i in 0..<20 {
            _ = try await store.create(
                question: "Q\(i)", answer: "A\(i)", sourceSpan: nil, now: seedDate
            )
        }

        let session = ReviewSession(
            store: store,
            scheduler: engine,
            clock: { seedDate }
        )
        await session.loadDueQueue()

        var submitDurationsNs: [Int64] = []

        for _ in 0..<20 {
            guard case .reviewing = session.state else { break }
            session.revealAnswer()

            let start = ContinuousClock.now
            await session.submit(grade: .good)
            let elapsed = ContinuousClock.now - start

            submitDurationsNs.append(
                elapsed.components.seconds * 1_000_000_000
                + Int64(elapsed.components.attoseconds / 1_000_000_000)
            )
        }

        // Also isolate the FSRS math cost separately (20 cold calls)
        let store2 = MockCardStore()
        var mathDurationsNs: [Int64] = []
        for i in 0..<20 {
            let snap = try await store2.create(
                question: "Q\(i)", answer: "A\(i)", sourceSpan: nil, now: seedDate
            )
            let start = ContinuousClock.now
            _ = try engine.next(card: snap.schedulingCard, rating: .good, now: seedDate)
            let elapsed = ContinuousClock.now - start
            mathDurationsNs.append(
                elapsed.components.seconds * 1_000_000_000
                + Int64(elapsed.components.attoseconds / 1_000_000_000)
            )
        }

        guard !submitDurationsNs.isEmpty else {
            Issue.record("No timing samples collected")
            return
        }

        let avg  = { (ns: [Int64]) in Double(ns.reduce(0, +)) / Double(ns.count) / 1_000_000 }
        let minV = { (ns: [Int64]) in Double(ns.min()!) / 1_000_000 }
        let maxV = { (ns: [Int64]) in Double(ns.max()!) / 1_000_000 }
        let pct  = { (ns: [Int64], p: Double) in
            let sorted = ns.sorted().map { Double($0) / 1_000_000 }
            return sorted[Int(Double(sorted.count) * p)]
        }

        let submitMaxMs = maxV(submitDurationsNs)
        let mathMaxMs   = maxV(mathDurationsNs)

        print("""
        ── review-tap latency (MockCardStore + LiveFSRS6Engine, \(submitDurationsNs.count) samples) ──
        submit() end-to-end (FSRS math + state mutations + MockStore.apply):
          avg:  \(String(format: "%.3f", avg(submitDurationsNs))) ms
          p50:  \(String(format: "%.3f", pct(submitDurationsNs, 0.5))) ms
          p95:  \(String(format: "%.3f", pct(submitDurationsNs, 0.95))) ms
          min:  \(String(format: "%.3f", minV(submitDurationsNs))) ms
          max:  \(String(format: "%.3f", submitMaxMs)) ms

        LiveFSRS6Engine.next() alone (\(mathDurationsNs.count) samples):
          avg:  \(String(format: "%.3f", avg(mathDurationsNs))) ms
          p50:  \(String(format: "%.3f", pct(mathDurationsNs, 0.5))) ms
          p95:  \(String(format: "%.3f", pct(mathDurationsNs, 0.95))) ms
          min:  \(String(format: "%.3f", minV(mathDurationsNs))) ms
          max:  \(String(format: "%.3f", mathMaxMs)) ms

        budget: submit() max < 100 ms ← \(submitMaxMs < 100 ? "PASS ✓" : "FAIL ✗")
        (Note: MockCardStore.apply is in-memory; add ~1-5 ms for real ModelContext.save
         per EndToEndReviewFlowTests in AnghkooeyCore — total still well under 100 ms)
        """)

        #expect(submitMaxMs < 100, "Worst-case review-tap exceeded 100 ms budget: \(submitMaxMs) ms")
        #expect(mathMaxMs < 50, "LiveFSRS6Engine.next() exceeded 50 ms: \(mathMaxMs) ms")
    }
}
