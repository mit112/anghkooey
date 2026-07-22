import Testing
import Foundation
import Observation
@testable import AnghkooeyUI

@Suite @MainActor struct OnboardingStateTests {
    @Test func defaultsToNotCompleted() {
        let d = UserDefaults(suiteName: "test.onboarding.\(UUID())")!
        let s = OnboardingState(defaults: d)
        #expect(s.hasCompleted == false)
    }
    @Test func completePersists() {
        let d = UserDefaults(suiteName: "test.onboarding.\(UUID())")!
        let s = OnboardingState(defaults: d)
        s.complete()
        #expect(s.hasCompleted == true)
        #expect(OnboardingState(defaults: d).hasCompleted == true)
    }
    /// The cover's binding reads `hasCompleted`; `complete()` must produce an
    /// observation event or the cover dismisses only by coincidence (#45).
    /// `confirmation` (Sendable) records the one-shot `onChange` fire without a
    /// captured-var mutation the `@Sendable` closure would reject under Swift 6.
    @Test func completeFiresObservation() async {
        let d = UserDefaults(suiteName: "test.onboarding.\(UUID())")!
        let s = OnboardingState(defaults: d)
        await confirmation("complete() emits an observation event") { confirm in
            withObservationTracking {
                _ = s.hasCompleted
            } onChange: {
                confirm()
            }
            s.complete()
        }
    }
}
