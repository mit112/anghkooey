import SwiftUI
import AnghkooeyCore

/// Dual-mode edit/create sheet used from the Library tab.
///
/// Delegates state management to `CardEditorViewModel`.
/// The `onSaved` callback triggers a data reload in `LibraryView`.
public struct LibraryCardEditView: View {

    @State private var model: CardEditorViewModel
    @Environment(\.dismiss) private var dismiss
    private let onSaved: () -> Void

    public init(mode: CardEditorViewModel.Mode,
                store: any CardStoreProtocol,
                onSaved: @escaping () -> Void) {
        _model = State(initialValue: CardEditorViewModel(mode: mode, store: store))
        self.onSaved = onSaved
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Question") {
                    TextField("Question", text: $model.question, axis: .vertical)
                        .lineLimit(3...)
                }
                Section("Answer") {
                    TextField("Answer", text: $model.answer, axis: .vertical)
                        .lineLimit(3...)
                }
                Section("Tags") {
                    TagEditorView(tags: $model.tags)
                }
            }
            .navigationTitle(model.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { try? await model.save(); onSaved(); dismiss() }
                    }
                    .disabled(!model.canSave)
                }
            }
        }
    }
}
