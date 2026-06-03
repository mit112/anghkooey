import Testing
@testable import AnghkooeyUI
import AnghkooeyIntelligence

@Suite struct CaptureAvailabilityModelTests {
    @Test func availableShowsAICapture() {
        let m = CaptureAvailabilityModel(availability: .available)
        #expect(m.shouldOfferAI == true)
        #expect(m.bannerMessage == nil)
    }
    @Test func deviceIneligibleRoutesToManualWithMessage() {
        let m = CaptureAvailabilityModel(availability: .unavailable(reason: .deviceNotEligible))
        #expect(m.shouldOfferAI == false)
        #expect(m.bannerMessage?.isEmpty == false)
    }
    @Test func aiOffMentionsSettings() {
        let m = CaptureAvailabilityModel(availability: .unavailable(reason: .appleIntelligenceNotEnabled))
        #expect(m.bannerMessage?.localizedCaseInsensitiveContains("settings") == true)
    }
}
