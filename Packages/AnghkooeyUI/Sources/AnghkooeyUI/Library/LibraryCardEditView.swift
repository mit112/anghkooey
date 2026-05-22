import SwiftUI
import AnghkooeyCore

/// Standalone edit sheet used from the Library tab.
///
/// Edits Q/A/tags directly via `store.update` — no ReviewSession involved.
/// The `onSave` callback triggers a data reload in `LibraryView`.
public struct LibraryCardEditView: View {

    @Environment(\.dismiss) private var dismiss
    let card: Card.Snapshot
    let store: any CardStoreProtocol
    let onSave: () -> Void

    @State private var editedQuestion: String
    @State private var editedAnswer: String
    @State private var editedTags: [String]

    public init(
        card: Card.Snapshot,
        store: any CardStoreProtocol,
        onSave: @escaping () -> Void
    ) {
        self.card = card
        self.store = store
        self.onSave = onSave
        _editedQuestion = State(initialValue: card.question)
        _editedAnswer = State(initialValue: card.answer)
        _editedTags = State(initialValue: card.tags)
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Question") {
                    TextEditor(text: $editedQuestion)
                        .frame(minHeight: 80)
                }
                Section("Answer") {
                    TextEditor(text: $editedAnswer)
                        .frame(minHeight: 80)
                }
                Section("Tags") {
                    TagEditorView(tags: $editedTags)
                }
            }
            .navigationTitle("Edit Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            try? await store.update(
                                id: card.id,
                                question: editedQuestion,
                                answer: editedAnswer,
                                tags: editedTags
                            )
                            onSave()
                            dismiss()
                        }
                    }
                }
            }
        }
    }
}
