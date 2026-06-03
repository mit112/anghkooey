import Testing
import Foundation
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
}
