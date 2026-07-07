import SwiftUI

/// Typed/pasted-text entry point into the AI card-authoring pipeline (#31).
///
/// foundation.md promises capture via photo, share, paste, *or* typing —
/// this view is the "typing" leg. It mirrors `CameraView`'s shape: a pure
/// SwiftUI view with no `AppState` dependency, handing resolved text back to
/// the caller via `onDraft` so it can be funnelled through the same
/// `AppState.enqueue(resolvedText:)` path the camera and clipboard capture
/// already use (same availability banner, drafting indicator, sheet queue).
public struct TypedTextCaptureView: View {

    @State private var text = ""
    private let onDraft: @MainActor @Sendable (String) -> Void

    public init(onDraft: @escaping @MainActor @Sendable (String) -> Void) {
        self.onDraft = onDraft
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextEditor(text: $text)
                .font(.body)
                .frame(minHeight: 160)
                .scrollContentBackground(.hidden)
                .background(Color(.systemFill), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityLabel("Passage to turn into cards")

            Text("Paste or type a passage — Anghkooey will draft cards from it.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Draft cards") {
                onDraft(text)
                text = ""
            }
            .buttonStyle(.borderedProminent)
            .disabled(!Self.isDraftable(text))
            .frame(maxWidth: .infinity)
        }
        .padding()
    }

    /// Whether `text` is worth sending into the authoring pipeline — gates
    /// the "Draft cards" button. Pulled into a static func so it's testable
    /// without a running view hierarchy (matches `CameraCaptureHandler`'s
    /// empty-OCR-output guard and `CaptureAvailabilityModel`'s pattern).
    static func isDraftable(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

#Preview("Typed text capture") {
    TypedTextCaptureView(onDraft: { _ in })
}
