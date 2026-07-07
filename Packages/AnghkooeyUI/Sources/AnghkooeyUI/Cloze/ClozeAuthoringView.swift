#if canImport(UIKit)
import SwiftUI
import AnghkooeyCore
import AnghkooeyIntelligence

// MARK: - ClozeAuthoringViewModel

@Observable
@MainActor
public final class ClozeAuthoringViewModel {
    public var markedText: String = "" {
        didSet { updatePreview() }
    }
    public var isGenerating: Bool = false
    public var detectedDeletions: [ClozeDeletion] = []
    public var errorMessage: String? = nil

    /// Tags most recently proposed by a successful `generate()` call, for
    /// the view to adopt when it doesn't already have tags of its own.
    public private(set) var proposedTags: [String] = []

    /// `markedText` as it stood immediately before the last successful
    /// `generate()` overwrote it. Non-nil only while a revert is possible —
    /// `revert()` and `accept(...)` both clear it. This is what lets the
    /// view offer a one-tap "Revert" instead of destroying the user's typed
    /// passage with no way back if the model mangles it (#25).
    public private(set) var preGenerationText: String? = nil
    public var canRevert: Bool { preGenerationText != nil }

    private let store: any CardStoreProtocol
    private let authoringService: any ClozeAuthoringService

    public init(store: any CardStoreProtocol, authoringService: any ClozeAuthoringService) {
        self.store = store
        self.authoringService = authoringService
    }

    public var canAccept: Bool { !detectedDeletions.isEmpty }

    public func accept(tags: [String] = [], now: Date = .now) async throws {
        errorMessage = nil
        do {
            let template = try ClozeMarkupParser.parse(markedText)
            _ = try await store.createClozeCards(from: template, tags: tags, now: now)
        } catch {
            UILog.cloze.error("accept() failed: \(error)")
            errorMessage = error.localizedDescription
            throw error
        }
        markedText = ""
        detectedDeletions = []
        preGenerationText = nil
        proposedTags = []
    }

    public func updatePreview() {
        detectedDeletions = (try? ClozeMarkupParser.parse(markedText))?.deletions ?? []
    }

    /// Streams AI-proposed cloze drafts for `markedText` and replaces it
    /// with the first non-empty draft.
    ///
    /// On failure `markedText` is left untouched (#25 — Generate must never
    /// destroy what the user typed) and `errorMessage` is set with copy that
    /// distinguishes "AI isn't available on this device" (no point
    /// retrying — the remedy is manual entry) from a generic, retryable
    /// failure. On success, the pre-generation text is retained so the view
    /// can offer a one-tap `revert()`. If the stream completes without ever
    /// producing a usable draft (the model can legitimately return an empty
    /// list) and without throwing, that is still a failure from the user's
    /// point of view, so `errorMessage` is set rather than leaving the user
    /// with no feedback at all (#25).
    public func generate() async {
        errorMessage = nil
        let preGenerationSnapshot = markedText
        isGenerating = true
        defer { isGenerating = false }
        do {
            let stream = try await authoringService.generateClozeDrafts(from: markedText)
            preGenerationText = preGenerationSnapshot
            var didApplyDraft = false
            for try await draft in stream {
                guard !draft.markedText.isEmpty else { continue }
                didApplyDraft = true
                markedText = draft.markedText
                proposedTags = draft.proposedTags
            }
            if !didApplyDraft && errorMessage == nil {
                UILog.cloze.error("generate() produced no usable cloze deletions")
                errorMessage = Self.noDeletionsFoundMessage
            }
        } catch let error as AuthoringError {
            UILog.cloze.error("generate() failed: \(error)")
            errorMessage = Self.errorMessage(for: error)
        } catch {
            UILog.cloze.error("generate() failed: \(error)")
            errorMessage = Self.genericFailureMessage
        }
    }

    /// Restores `markedText` to what it was right before the last
    /// successful `generate()` replaced it, then clears the revert
    /// affordance so the button disappears again.
    public func revert() {
        guard let preGenerationText else { return }
        markedText = preGenerationText
        self.preGenerationText = nil
        proposedTags = []
    }

    private static let genericFailureMessage = "Couldn't generate cloze deletions — try again."
    private static let noDeletionsFoundMessage = "No cloze deletions found — try rewording or add markers yourself."

    /// Maps `AuthoringError` to user-facing copy, distinguishing an
    /// unavailable on-device model (whose remedy is to write `{{c1::...}}`
    /// deletions by hand) from a generic, retryable generation failure.
    private static func errorMessage(for error: AuthoringError) -> String {
        switch error {
        case .unavailable:
            return "On-device AI isn't available on this device. Add {{c1::deletion}} markers yourself instead."
        case .emptyInput, .generationFailed:
            return genericFailureMessage
        }
    }
}

// MARK: - ClozeAuthoringView

public struct ClozeAuthoringView: View {
    @State private var vm: ClozeAuthoringViewModel
    @State private var tags: [String] = []

    public init(store: any CardStoreProtocol, authoringService: any ClozeAuthoringService) {
        _vm = State(initialValue: ClozeAuthoringViewModel(store: store, authoringService: authoringService))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Markup passage with {{c1::answer}} markers")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextEditor(text: $vm.markedText)
                .frame(minHeight: 120)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))
                // Disabled while streaming so a mid-stream draft can't silently
                // clobber a user's edit — the model can yield multiple drafts
                // across suspension points (#25).
                .disabled(vm.isGenerating)

            if !vm.detectedDeletions.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Detected deletions:")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(vm.detectedDeletions, id: \.index) { d in
                        Text("c\(d.index): \(d.answer)")
                            .font(.caption2).foregroundStyle(.primary)
                    }
                }
            }

            TagEditorView(tags: $tags)

            HStack {
                Button("Generate") {
                    Task { @MainActor in
                        await vm.generate()
                        if tags.isEmpty { tags = vm.proposedTags }
                    }
                }
                .buttonStyle(.bordered)
                .disabled(vm.markedText.trimmingCharacters(in: .whitespaces).isEmpty || vm.isGenerating)

                if vm.canRevert {
                    Button("Revert") {
                        vm.revert()
                    }
                    .buttonStyle(.bordered)
                    // Same reentrancy guard as the editor above — revert
                    // must not race a still-streaming generate() (#25).
                    .disabled(vm.isGenerating)
                }

                Spacer()

                Button("Accept") {
                    Task {
                        do {
                            try await vm.accept(tags: tags)
                        } catch {
                            // errorMessage already set on vm by accept()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!vm.canAccept || vm.isGenerating)
            }

            if let msg = vm.errorMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .navigationTitle("Cloze Card")
    }
}
#endif
