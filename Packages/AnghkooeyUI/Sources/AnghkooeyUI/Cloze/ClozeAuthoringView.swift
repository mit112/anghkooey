#if canImport(UIKit)
import SwiftUI
import AnghkooeyCore
import AnghkooeyIntelligence

// MARK: - ClozeAuthoringViewModel

@Observable
@MainActor
public final class ClozeAuthoringViewModel {
    public var markedText: String = ""
    public var isGenerating: Bool = false
    public var detectedDeletions: [ClozeDeletion] = []

    private let store: any CardStoreProtocol

    public init(store: any CardStoreProtocol) {
        self.store = store
    }

    public var canAccept: Bool {
        (try? ClozeMarkupParser.parse(markedText)) != nil
    }

    public func accept(tags: [String] = [], now: Date = .now) async throws {
        let template = try ClozeMarkupParser.parse(markedText)
        _ = try await store.createClozeCards(from: template, tags: tags, now: now)
        markedText = ""
        detectedDeletions = []
    }

    public func updatePreview() {
        detectedDeletions = (try? ClozeMarkupParser.parse(markedText))?.deletions ?? []
    }
}

// MARK: - ClozeAuthoringView

public struct ClozeAuthoringView: View {
    @State private var vm: ClozeAuthoringViewModel
    private let authoringService: any ClozeAuthoringService
    @State private var tags: [String] = []

    public init(store: any CardStoreProtocol, authoringService: any ClozeAuthoringService) {
        _vm = State(initialValue: ClozeAuthoringViewModel(store: store))
        self.authoringService = authoringService
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Markup passage with {{c1::answer}} markers")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextEditor(text: $vm.markedText)
                .frame(minHeight: 120)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))
                .onChange(of: vm.markedText) { _, _ in vm.updatePreview() }

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
                    Task { @MainActor in await generate() }
                }
                .buttonStyle(.bordered)
                .disabled(vm.markedText.trimmingCharacters(in: .whitespaces).isEmpty || vm.isGenerating)

                Spacer()

                Button("Accept") {
                    Task { @MainActor in
                        try? await vm.accept(tags: tags)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!vm.canAccept)
            }
        }
        .padding()
        .navigationTitle("Cloze Card")
    }

    @MainActor
    private func generate() async {
        vm.isGenerating = true
        defer { vm.isGenerating = false }
        do {
            let stream = try await authoringService.generateClozeDrafts(from: vm.markedText)
            for try await draft in stream {
                if !draft.markedText.isEmpty {
                    vm.markedText = draft.markedText
                    if tags.isEmpty { tags = draft.proposedTags }
                }
            }
        } catch {
            // Non-fatal — user can still edit manually
        }
    }
}
#endif
