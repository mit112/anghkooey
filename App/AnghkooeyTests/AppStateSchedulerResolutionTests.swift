import Testing
import Foundation
@testable import Anghkooey
import AnghkooeyCore

@Suite("AppState scheduler resolution")
@MainActor
struct AppStateSchedulerResolutionTests {

    private struct StubError: Error {}

    @Test("under-threshold history resolves to default params")
    func defaultUnderThreshold() async {
        let store = MockCardStore()   // empty → 0 eligible
        let appState = AppState(cardStore: store)
        await appState.refreshScheduler()
        let engine = appState.scheduler as? LiveFSRS6Engine
        #expect(engine?.parameters == FSRSParameters.default)
    }

    @Test("above-threshold with saved optimized params uses optimized scheduler")
    func optimizedParamsFlowThroughToScheduler() async throws {
        let store = MockCardStore()

        // OptimizationDataset caps each card's sequence to maxSequenceLength (200).
        // Within the capped sequence index-0 is ineligible, so each card contributes
        // at most 199 eligible samples. Use 3 cards × 201 reviews each → 3 × 199 = 597 eligible.
        var rows: [OptimizationReviewLogRow] = []
        for _ in 0..<3 {
            let id = UUID()
            for day in 0...200 {
                rows.append(.init(cardID: id, reviewedAt: Date(timeIntervalSince1970: Double(day) * 86_400), rating: .good, elapsedDays: day == 0 ? 0 : 1))
            }
        }
        store.optimizationReviewLogsOverride = rows

        let appState = AppState(cardStore: store)

        // Save a non-default weight set directly to the store AppState owns.
        var w = FSRSParameters.default.w
        w[8] += 0.5
        let optimized = FSRSParameters.default.withWeights(w)
        try appState.optimizedParamsStore.save(optimized)

        await appState.refreshScheduler()
        let engine = appState.scheduler as? LiveFSRS6Engine
        #expect(engine?.parameters == optimized)
    }

    @Test("a store failure during refreshScheduler() keeps the existing scheduler instead of reverting to default (#27 fix 3)")
    func storeFailureKeepsExistingSchedulerInsteadOfReverting() async throws {
        let store = MockCardStore()

        // Same eligible-count construction as
        // `optimizedParamsFlowThroughToScheduler`: 3 cards × 201 reviews
        // each → 3 × 199 = 597 eligible, above the 512 threshold.
        var rows: [OptimizationReviewLogRow] = []
        for _ in 0..<3 {
            let id = UUID()
            for day in 0...200 {
                rows.append(.init(cardID: id, reviewedAt: Date(timeIntervalSince1970: Double(day) * 86_400), rating: .good, elapsedDays: day == 0 ? 0 : 1))
            }
        }
        store.optimizationReviewLogsOverride = rows

        let appState = AppState(cardStore: store)

        var w = FSRSParameters.default.w
        w[8] += 0.5
        let optimized = FSRSParameters.default.withWeights(w)
        try appState.optimizedParamsStore.save(optimized)

        // First refresh succeeds and picks up the optimized params.
        await appState.refreshScheduler()
        let engineBefore = appState.scheduler as? LiveFSRS6Engine
        #expect(engineBefore?.parameters == optimized)

        // A transient store read failure on a later refresh (e.g. via a
        // drain, or SettingsView's `onOptimized` callback) must not coerce
        // eligible-count to 0 and silently revert the live scheduler to
        // `.default` — the prior scheduler/widget reconciler must survive
        // untouched.
        store.optimizationReviewLogsError = StubError()
        await appState.refreshScheduler()
        let engineAfter = appState.scheduler as? LiveFSRS6Engine
        #expect(engineAfter?.parameters == optimized)
    }
}
