import SwiftUI
import AnghkooeyCore

/// Dual-mode edit/create sheet used from the Library tab.
///
/// Delegates state management to `CardEditorViewModel`.
/// The `onSaved` callback triggers a data reload in `LibraryView`.
public struct LibraryCardEditView: View {

    @State private var model: CardEditorViewModel
    @State private var isPresentingDeleteConfirm = false
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
                if model.isCreateMode {
                    Picker("Card type", selection: $model.kind) {
                        Text("Q&A").tag(CardEditorViewModel.Kind.qa)
                        Text("Cloze").tag(CardEditorViewModel.Kind.cloze)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Card type: \(model.kind == .qa ? "Question and Answer" : "Cloze deletion")")
                }
                if model.kind == .cloze {
                    Section("Cloze sentence") {
                        TextField("e.g. The capital of France is {{c1::Paris}}.",
                                  text: $model.clozeText,
                                  axis: .vertical)
                            .lineLimit(3...)
                        if let t = try? ClozeMarkupParser.parse(model.clozeText), !t.deletions.isEmpty {
                            Text("\(t.deletions.count) deletion\(t.deletions.count == 1 ? "" : "s") detected")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Section("Question") {
                        TextField("Question", text: $model.question, axis: .vertical)
                            .lineLimit(3...)
                    }
                    Section("Answer") {
                        TextField("Answer", text: $model.answer, axis: .vertical)
                            .lineLimit(3...)
                    }
                }
                Section("Tags") {
                    TagEditorView(tags: $model.tags)
                }
                if let msg = model.errorMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                if !model.isCreateMode {
                    Section {
                        Button("Delete Card", role: .destructive) {
                            isPresentingDeleteConfirm = true
                        }
                    }
                }
            }
            .navigationTitle(model.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog(
                "Delete this card?",
                isPresented: $isPresentingDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete Card", role: .destructive) {
                    Task {
                        do {
                            try await model.delete()
                            if let id = model.editingCardID {
                                NotificationCenter.default.post(name: .anghkooeyDeckDidChange, object: id)
                            }
                            onSaved()
                            dismiss()
                        } catch {
                            // Already logged and surfaced via model.errorMessage;
                            // the sheet just stays open so the user sees it.
                            model.surfaceFallbackErrorIfNeeded()
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This can't be undone.")
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    HStack(spacing: 8) {
                        if model.isSaving {
                            ProgressView()
                        }
                        Button("Save") {
                            Task {
                                do {
                                    try await model.save()
                                    onSaved()
                                    dismiss()
                                } catch {
                                    // Already logged and surfaced via model.errorMessage (#26);
                                    // the sheet just stays open so the user sees it. Self-healing
                                    // backstop in case a future save() path throws without
                                    // setting errorMessage — the user still sees *something*.
                                    model.surfaceFallbackErrorIfNeeded()
                                }
                            }
                        }
                        // isSaving guards against a double-tap re-entering save()
                        // and double-creating a card in create mode (#26).
                        .disabled(!model.canSave || model.isSaving)
                        .accessibilityHint(model.canSave ? "" : "Fill in all required fields to enable")
                    }
                }
            }
        }
    }
}
