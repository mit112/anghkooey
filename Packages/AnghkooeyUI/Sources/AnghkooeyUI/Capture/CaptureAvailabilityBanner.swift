import SwiftUI
import AnghkooeyIntelligence

/// Dismissible capture-tab banner explaining why on-device AI card
/// generation isn't available, driven by `CaptureAvailabilityModel` (#30).
///
/// Renders nothing (`EmptyView()`) when `availability` is `.available` —
/// `CaptureAvailabilityModel.bannerMessage` is `nil` in that case, so there's
/// nothing to explain and no banner to show. Visual language matches
/// `ErrorToastView`'s banner: `HStack` icon + message + `.thinMaterial`
/// rounded card, with a plain `xmark` dismiss button.
public struct CaptureAvailabilityBanner: View {
    public let availability: AuthoringAvailability
    public let onDismiss: () -> Void

    public init(availability: AuthoringAvailability, onDismiss: @escaping () -> Void) {
        self.availability = availability
        self.onDismiss = onDismiss
    }

    public var body: some View {
        if let message = CaptureAvailabilityModel(availability: availability).bannerMessage {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.circle")
                    .accessibilityHidden(true)
                Text(message)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
            .padding(12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal)
            .transition(.move(edge: .top).combined(with: .opacity))
            .accessibilityIdentifier("capture-availability-banner")
        } else {
            EmptyView()
        }
    }
}

#Preview("Available — no banner") {
    CaptureAvailabilityBanner(availability: .available, onDismiss: {})
}

#Preview("Device not eligible") {
    CaptureAvailabilityBanner(availability: .unavailable(reason: .deviceNotEligible), onDismiss: {})
}

#Preview("Apple Intelligence not enabled") {
    CaptureAvailabilityBanner(availability: .unavailable(reason: .appleIntelligenceNotEnabled), onDismiss: {})
}

#Preview("Model downloading") {
    CaptureAvailabilityBanner(availability: .unavailable(reason: .modelNotReady), onDismiss: {})
}
