import Testing
import Foundation
@testable import AnghkooeyCore

@Suite("OptimizedParametersStore")
struct OptimizedParametersStoreTests {
    private func tempStore() -> OptimizedParametersStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return OptimizedParametersStore(containerURL: dir)
    }

    @Test("under threshold returns default regardless of stored value")
    func underThresholdReturnsDefault() throws {
        let store = tempStore()
        var w = FSRSParameters.default.w; w[8] += 1.0
        try store.save(FSRSParameters.default.withWeights(w))
        let resolved = store.resolveParameters(eligibleSampleCount: 511)
        #expect(resolved == FSRSParameters.default)
    }

    @Test("at/above threshold returns stored optimized set")
    func atThresholdReturnsStored() throws {
        let store = tempStore()
        var w = FSRSParameters.default.w; w[8] += 1.0
        let optimized = FSRSParameters.default.withWeights(w)
        try store.save(optimized)
        #expect(store.resolveParameters(eligibleSampleCount: 512) == optimized)
    }

    @Test("above threshold with no stored value falls back to default")
    func noStoredValueFallsBack() {
        let store = tempStore()
        #expect(store.resolveParameters(eligibleSampleCount: 5000) == FSRSParameters.default)
    }

    @Test("persists across store instances (same container)")
    func persistsAcrossInstances() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var w = FSRSParameters.default.w; w[0] += 0.5
        try OptimizedParametersStore(containerURL: dir).save(FSRSParameters.default.withWeights(w))
        let reloaded = OptimizedParametersStore(containerURL: dir).resolveParameters(eligibleSampleCount: 1000)
        #expect(reloaded.w[0] == FSRSParameters.default.w[0] + 0.5)
    }

    @Test("threshold constant is 512")
    func thresholdValue() { #expect(OptimizedParametersStore.threshold == 512) }
}
