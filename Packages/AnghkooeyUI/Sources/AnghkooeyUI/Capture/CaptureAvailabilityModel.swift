import Foundation
import AnghkooeyIntelligence

/// Maps on-device model availability into capture-screen UX decisions.
public struct CaptureAvailabilityModel: Sendable, Equatable {
    public let availability: AuthoringAvailability
    public init(availability: AuthoringAvailability) { self.availability = availability }

    public var shouldOfferAI: Bool {
        if case .available = availability { return true }
        return false
    }

    public var bannerMessage: String? {
        switch availability {
        case .available:
            return nil
        case .unavailable(.deviceNotEligible):
            return "On-device card generation isn't supported on this device. You can still add cards by hand."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence in Settings to auto-generate cards. For now, add cards by hand."
        case .unavailable(.modelNotReady):
            return "The on-device model is still downloading. You can add cards by hand in the meantime."
        }
    }
}
