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
    public private(set) var errorMessage: String?

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

    /// The id of the card being edited, or `nil` in create mode. Lets the
    /// view post `.anghkooeyDeckDidChange` after a successful `delete()`
    /// without needing to know about `Mode` itself (#38).
    public var editingCardID: UUID? {
        if case let .edit(card) = mode { return card.id }
        return nil
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

    /// Persists the current question/answer/tags via the store.
    ///
    /// On failure, `errorMessage` is set and the error is rethrown so the
    /// sheet stays open — entered data (question/answer/tags) lives on this
    /// model and is never cleared here, so a failed save doesn't destroy
    /// what the user typed (#26). `isSaving` guards against a double-tap
    /// re-entering `save()` while the first attempt is still in flight: a
    /// second overlapping call is a no-op, matching the guard already used
    /// by `AppState.acceptDraft`.
    public func save() async throws {
        guard !isSaving else { return }
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let a = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }
        do {
            switch mode {
            case .create:
                switch kind {
                case .qa:
                    _ = try await store.create(question: q, answer: a, sourceSpan: nil, tags: tags, now: .now)
                case .cloze:
                    // Must throw (not silently `return`) on unparseable markup —
                    // a bare return here would make `save()` complete without
                    // throwing, so the view would treat it as a success and
                    // close the sheet with nothing persisted (#26).
                    let template = try ClozeMarkupParser.parse(clozeText)
                    _ = try await store.createClozeCards(from: template, tags: tags, now: .now)
                }
            case let .edit(card):
                try await store.update(id: card.id, question: q, answer: a, tags: tags)
            }
        } catch {
            UILog.library.error("Card save failed: \(error)")
            errorMessage = Self.errorMessage(for: error)
            throw error
        }
    }

    /// Deletes the card being edited. Edit mode only — a no-op in create
    /// mode, since there's nothing persisted yet to delete.
    ///
    /// On failure, `errorMessage` is set and the error is rethrown so the
    /// sheet stays open (mirrors `save()`'s contract, #38).
    public func delete() async throws {
        guard case let .edit(card) = mode else { return }
        errorMessage = nil
        do {
            try await store.delete(id: card.id)
        } catch {
            UILog.library.error("Card delete failed: \(error)")
            errorMessage = Self.errorMessage(for: error)
            throw error
        }
    }

    /// Sets `errorMessage` to a generic fallback if nothing has already
    /// surfaced one. Defense-in-depth backstop for a caller (the view's
    /// `save()` catch block) that observed a throw but found no message —
    /// `errorMessage` stays `private(set)`, so this is the seam through
    /// which the view can self-heal without the model losing control of
    /// its own invariant (#26).
    public func surfaceFallbackErrorIfNeeded() {
        if errorMessage == nil {
            errorMessage = "Save failed. Please try again."
        }
    }

    /// Maps a save failure to user-facing copy. `ClozeParseError` doesn't
    /// conform to `LocalizedError`, so its bridged `localizedDescription`
    /// is a generic, unhelpful NSError message ("The operation couldn't be
    /// completed...") — spell out what's actually wrong with the markup so
    /// the user has something actionable to fix (#26).
    private static func errorMessage(for error: Error) -> String {
        guard let clozeError = error as? ClozeParseError else {
            return error.localizedDescription
        }
        switch clozeError {
        case .noDeletions:
            return "No cloze deletions found — add at least one {{c1::answer}} marker."
        case .unclosedMarker:
            return "Unclosed {{ marker — check for a missing }}."
        case .nestedMarker:
            return "Nested {{ }} markers aren't supported."
        case let .duplicateIndex(index):
            return "Duplicate cloze index c\(index) — each deletion needs a unique number."
        case let .nonPositiveIndex(index):
            return "Cloze index must be positive (found c\(index))."
        case let .tooManyDeletions(count, max):
            return "Too many cloze deletions (\(count) found, max \(max))."
        case let .emptyAnswer(index):
            return "Cloze c\(index) has an empty answer — add text after ::."
        }
    }
}
