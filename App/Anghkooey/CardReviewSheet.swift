import SwiftUI
import AnghkooeyIntelligence

/// Review sheet for a single AI-authored card draft.
///
/// Shows editable Question and Answer fields, plus a collapsed read-only
/// source span. The user may edit Q/A before accepting; edits are passed
/// through `onAccept(question:answer:)`.
struct CardReviewSheet: View {
    let draft: IdentifiedDraft
    let onAccept: (String, String) -> Void
    let onSkip: () -> Void

    /// This draft's position within its capture's batch, e.g. `(2, 5)` for
    /// "Card 2 of 5" — see `AppState.presentedDraftProgress`. `nil` when the
    /// caller doesn't have an `AppState` to source it from (tests, previews);
    /// defaults to `nil` so existing call sites keep compiling unchanged.
    var progress: (position: Int, total: Int)?

    @State private var editedQuestion: String
    @State private var editedAnswer: String

    init(
        draft: IdentifiedDraft,
        onAccept: @escaping (String, String) -> Void,
        onSkip: @escaping () -> Void,
        progress: (position: Int, total: Int)? = nil
    ) {
        self.draft = draft
        self.onAccept = onAccept
        self.onSkip = onSkip
        self.progress = progress
        _editedQuestion = State(initialValue: draft.draft.question)
        _editedAnswer = State(initialValue: draft.draft.answer)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let progress, progress.total > 1 {
                        Text("Card \(progress.position) of \(progress.total)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if draft.isFallback {
                        Text("AI unavailable — edit this card by hand.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    editableFieldSection(label: "Question", text: $editedQuestion)
                    editableFieldSection(label: "Answer", text: $editedAnswer)
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
                    Button("Accept") {
                        onAccept(editedQuestion, editedAnswer)
                    }
                }
            }
        }
    }

    // MARK: - Private helpers

    private func editableFieldSection(label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            TextEditor(text: text)
                .font(.body)
                .frame(minHeight: 80)
                .scrollContentBackground(.hidden)
                .background(Color(.systemFill), in: RoundedRectangle(cornerRadius: 8))
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
