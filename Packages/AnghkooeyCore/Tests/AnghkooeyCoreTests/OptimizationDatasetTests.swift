import Testing
import Foundation
@testable import AnghkooeyCore

@Suite("OptimizationDataset")
struct OptimizationDatasetTests {
    private func row(_ card: UUID, _ day: Int, _ rating: Rating, elapsed: Double) -> OptimizationReviewLogRow {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        return OptimizationReviewLogRow(
            cardID: card,
            reviewedAt: base.addingTimeInterval(Double(day) * 86_400),
            rating: rating,
            elapsedDays: elapsed
        )
    }

    @Test("groups rows by card and orders by reviewedAt")
    func grouping() {
        let a = UUID(), b = UUID()
        let rows = [
            row(a, 2, .good, elapsed: 2),
            row(b, 0, .again, elapsed: 0),
            row(a, 0, .good, elapsed: 0),   // out of order on purpose
        ]
        let ds = OptimizationDataset(rows: rows)
        #expect(ds.cardSequences.count == 2)
        // Card a: two reviews, ordered day0 then day2
        let seqA = ds.cardSequences.first { $0.count == 2 }!
        #expect(seqA[0].elapsedDays == 0)
        #expect(seqA[1].elapsedDays == 2)
    }

    @Test("eligible = non-first AND non-same-day")
    func eligibility() {
        let c = UUID()
        // first(day0,e0) | same-day(day0,e0) | real(day3,e3) | real(day10,e7)
        let rows = [
            row(c, 0, .good, elapsed: 0),
            row(c, 0, .hard, elapsed: 0),   // same-day → excluded
            row(c, 3, .good, elapsed: 3),   // eligible
            row(c, 10, .good, elapsed: 7),  // eligible
        ]
        let ds = OptimizationDataset(rows: rows)
        #expect(ds.eligibleSampleCount == 2)
    }

    @Test("first review is never eligible even if elapsed > 0")
    func firstNeverEligible() {
        let c = UUID()
        let rows = [row(c, 5, .good, elapsed: 5)] // single first review
        let ds = OptimizationDataset(rows: rows)
        #expect(ds.eligibleSampleCount == 0)
    }

    @Test("sequence longer than cap keeps the most recent N")
    func cap() {
        let c = UUID()
        let n = OptimizationDataset.maxSequenceLength
        var rows: [OptimizationReviewLogRow] = []
        for day in 0...(n + 50) { rows.append(row(c, day, .good, elapsed: day == 0 ? 0 : 1)) }
        let ds = OptimizationDataset(rows: rows)
        #expect(ds.cardSequences[0].count == n)
    }

    @Test("sameDay flag set iff elapsedDays == 0")
    func sameDayFlag() {
        let c = UUID()
        let rows = [row(c, 0, .good, elapsed: 0), row(c, 1, .good, elapsed: 1)]
        let ds = OptimizationDataset(rows: rows)
        #expect(ds.cardSequences[0][0].sameDay == true)
        #expect(ds.cardSequences[0][1].sameDay == false)
    }
}
