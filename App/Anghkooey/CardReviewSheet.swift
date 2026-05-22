import SwiftUI
import AnghkooeyIntelligence

/// Review sheet for a single AI-authored card draft.
///
/// Shows Question, Answer, and an optional collapsed source span.
/// Both fields are read-only in v1; editing-before-accept is M5.
struct CardReviewSheet: View {
    let draft: IdentifiedDraft
    let onAccept: () -> Void
    let onSkip: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    fieldSection(label: "Question", text: draft.draft.question)
                    fieldSection(label: "Answer", text: draft.draft.answer)
                    if let span = draft.draft.sourceSpan {
                        sourceSection(span: span)
                    }
                }
                .padding()
            }
            .navigationTitle("Review Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip", action: onSkip)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Accept", action: onAccept)
                }
            }
        }
    }

    // MARK: - Private helpers

    private func fieldSection(label: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(text)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func sourceSection(span: String) -> some View {
        DisclosureGroup {
            Text(span)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
        } label: {
            Text("Source")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
        }
    }
}
