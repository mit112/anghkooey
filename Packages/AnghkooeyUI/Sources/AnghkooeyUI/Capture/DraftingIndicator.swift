import SwiftUI

/// Compact top banner shown while `AppState.authoringCount > 0` — the gap
/// between a capture (camera shutter / clipboard "Use" / share-drain) and the
/// draft sheet appearing, during which on-device generation is running with
/// otherwise no visible feedback (#34).
///
/// Visual language matches `ClipboardBanner`/`CaptureAvailabilityBanner`/
/// `ErrorToastView`'s banner: `HStack` + `.thinMaterial` rounded card. The
/// spinner and label are exposed to VoiceOver as a single accessible element
/// ("Drafting cards") rather than two separate ones.
public struct DraftingIndicator: View {
    public init() {}

    public var body: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text("Drafting cards…")
                .font(.subheadline.weight(.semibold))
            Spacer()
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal)
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Drafting cards")
        .accessibilityIdentifier("drafting-indicator")
    }
}

#Preview("Drafting") {
    DraftingIndicator()
}
