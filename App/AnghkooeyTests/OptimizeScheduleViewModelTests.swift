import Testing
import Foundation
@testable import Anghkooey
@testable import AnghkooeyCore
import AnghkooeyUI

@MainActor
@Suite("OptimizeScheduleViewModel")
struct OptimizeScheduleViewModelTests {
    @Test("under threshold shows locked state with eligible count")
    func lockedState() async {
        let vm = OptimizeScheduleViewModel(
            store: MockCardStore(),
            optimizer: MockFSRSOptimizer(),
            paramsStore: OptimizedParametersStore(containerURL: FileManager.default.temporaryDirectory))
        await vm.refresh()
        #expect(vm.isUnlocked == false)
        #expect(vm.eligibleSampleCount == 0)
        #expect(vm.unlockThreshold == 512)
    }

    @Test("running the optimizer publishes progress then a result")
    func runProducesResult() async {
        let vm = OptimizeScheduleViewModel(
            store: MockCardStore(),
            optimizer: MockFSRSOptimizer(),
            paramsStore: OptimizedParametersStore(containerURL: FileManager.default.temporaryDirectory))
        await vm.optimize()
        #expect(vm.result?.optimizedLoss == 0.42)
        #expect(vm.progress == 1.0)
    }
}
