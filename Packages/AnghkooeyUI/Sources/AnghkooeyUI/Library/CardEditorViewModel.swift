import Foundation
import Observation
import AnghkooeyCore

@MainActor @Observable
public final class CardEditorViewModel {

    public enum Mode: Equatable {
        case create
        case edit(Card.Snapshot)
    }

    public enum Kind: Equatable {
        case qa, cloze
    }

    public var question: String = ""
    public var answer: String = ""
    public var tags: [String] = []
    public var kind: Kind = .qa
    public var clozeText: String = ""
    public private(set) var isSaving = false

    private let mode: Mode
    private let store: any CardStoreProtocol

    public init(mode: Mode, store: any CardStoreProtocol) {
        self.mode = mode
        self.store = store
        if case let .edit(card) = mode {
            question = card.question
            answer = card.answer
            tags = card.tags
        }
    }

    public var navigationTitle: String {
        if case .create = mode { return "New Card" } else { return "Edit Card" }
    }

    public var isCreateMode: Bool {
        if case .create = mode { return true }
        return false
    }

    private var parsedCloze: ClozeTemplate? {
        try? ClozeMarkupParser.parse(clozeText)
    }

    public var canSave: Bool {
        guard !isSaving else { return false }
        switch kind {
        case .qa:
            return !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .cloze:
            guard let t = parsedCloze else { return false }
            return !t.deletions.isEmpty
        }
    }

    public func save() async throws {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let a = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        isSaving = true
        defer { isSaving = false }
        switch mode {
        case .create:
            switch kind {
            case .qa:
                _ = try await store.create(question: q, answer: a, sourceSpan: nil, tags: tags, now: .now)
            case .cloze:
                guard let template = parsedCloze else { return }
                _ = try await store.createClozeCards(from: template, tags: tags, now: .now)
            }
        case let .edit(card):
            try await store.update(id: card.id, question: q, answer: a, tags: tags)
        }
    }
}
