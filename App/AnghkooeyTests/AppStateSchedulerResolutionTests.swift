import Testing
import Foundation
@testable import Anghkooey
import AnghkooeyCore

@Suite("AppState scheduler resolution")
@MainActor
struct AppStateSchedulerResolutionTests {
    @Test("under-threshold history resolves to default params")
    func defaultUnderThreshold() async {
        let store = MockCardStore()   // empty → 0 eligible
        let appState = AppState(cardStore: store)
        await appState.refreshScheduler()
        let engine = appState.scheduler as? LiveFSRS6Engine
        #expect(engine?.parameters == FSRSParameters.default)
    }
}
