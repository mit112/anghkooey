import SwiftUI

struct ClipboardBanner: View {
    let coordinator: ClipboardCaptureCoordinator

    var body: some View {
        if coordinator.pendingOffer != nil {
            HStack(spacing: 12) {
                Image(systemName: "doc.on.clipboard")
                Text("Create cards from clipboard?")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("Use") { coordinator.acceptOffer() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Button { coordinator.dismissOffer() } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
            .padding(12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal)
            .transition(.move(edge: .top).combined(with: .opacity))
            .accessibilityIdentifier("clipboard-banner")
        }
    }
}
