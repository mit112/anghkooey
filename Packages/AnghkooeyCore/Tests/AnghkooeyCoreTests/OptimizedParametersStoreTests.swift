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

    // MARK: - #85: corrupt-file diagnostics

    private func tempDirAndFile() -> (dir: URL, file: URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (dir, dir.appendingPathComponent("optimized-fsrs-params.json"))
    }

    @Test("readValidatedParameters returns params matching the written weights")
    func readValidatedParametersReturnsWrittenWeights() throws {
        let (dir, _) = tempDirAndFile()
        var w = FSRSParameters.default.w; w[3] += 2.0
        let store = OptimizedParametersStore(containerURL: dir)
        try store.save(FSRSParameters.default.withWeights(w))

        let params = try store.readValidatedParameters()
        #expect(params.w == w)
    }

    @Test("readValidatedParameters throws on corrupt (non-JSON) bytes")
    func readValidatedParametersThrowsOnCorruptBytes() throws {
        let (_, file) = tempDirAndFile()
        try Data("not json at all {{{".utf8).write(to: file, options: .atomic)
        let store = OptimizedParametersStore(containerURL: file.deletingLastPathComponent())

        #expect(throws: (any Error).self) {
            try store.readValidatedParameters()
        }
    }

    @Test("readValidatedParameters throws invalidWeightCount on wrong-shape JSON")
    func readValidatedParametersThrowsOnWrongWeightCount() throws {
        let (_, file) = tempDirAndFile()
        let badBlob = ["w": [1.0, 2.0, 3.0]]
        let data = try JSONEncoder().encode(badBlob)
        try data.write(to: file, options: .atomic)
        let store = OptimizedParametersStore(containerURL: file.deletingLastPathComponent())

        #expect(throws: OptimizedParametersLoadError.invalidWeightCount(3)) {
            try store.readValidatedParameters()
        }
    }

    @Test("loadOptimized returns nil silently when file is absent")
    func loadOptimizedReturnsNilWhenAbsent() {
        let (dir, _) = tempDirAndFile()
        let store = OptimizedParametersStore(containerURL: dir)
        #expect(store.loadOptimized() == nil)
    }

    @Test("loadOptimized returns nil (after logging) when file is corrupt")
    func loadOptimizedReturnsNilWhenCorrupt() throws {
        let (_, file) = tempDirAndFile()
        try Data("garbage".utf8).write(to: file, options: .atomic)
        let store = OptimizedParametersStore(containerURL: file.deletingLastPathComponent())
        #expect(store.loadOptimized() == nil)
    }

    @Test("loadOptimized returns params for a valid file")
    func loadOptimizedReturnsParamsForValidFile() throws {
        let (dir, _) = tempDirAndFile()
        var w = FSRSParameters.default.w; w[5] += 1.5
        let store = OptimizedParametersStore(containerURL: dir)
        try store.save(FSRSParameters.default.withWeights(w))

        #expect(store.loadOptimized()?.w == w)
    }
}
