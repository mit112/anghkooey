import Foundation
import OSLog

struct MappedCard {
    let question: String
    let answer: String
    let tags: [String]
    let dueAt: Date
    let sourceSpan: String   // "anki:<noteId>:<cardOrd>"
}

public enum AnkiNoteMapper {

    /// Returns the stable source-span identifier for one card ordinal from an Anki note.
    public static func sourceSpan(noteID: Int, cardOrd: Int) -> String {
        "anki:\(noteID):\(cardOrd)"
    }

    /// Returns true if the model name indicates a cloze note type.
    /// Cloze import is deferred past v2; skip rather than corrupt.
    public static func isClozeModel(name: String) -> Bool {
        name.localizedCaseInsensitiveContains("cloze")
    }

    /// Returns `nil` if the note should be skipped (cloze, non-Basic, or missing Front/Back fields).
    static func map(note: AnkiNote, collection: AnkiCollection, importedAt: Date) -> MappedCard? {
        guard let model = collection.models[note.modelID] else { return nil }

        if model.type == 1 {
            CoreLog.ankiImport.debug("Skipping cloze note \(note.id, privacy: .public) (modelID: \(model.id, privacy: .public))")
            return nil
        }

        guard isBasic(model) else { return nil }
        guard note.fields.count >= 2 else { return nil }

        let question = HTMLSanitizer.process(note.fields[0])
        let answer   = HTMLSanitizer.process(note.fields[1])

        let deckName = collection.deckNames[note.deckID] ?? "Default"
        let tags = deckName.components(separatedBy: "::").filter { !$0.isEmpty }

        let due = resolvedDue(note: note, collectionCreatedAt: collection.createdAt, importedAt: importedAt)

        return MappedCard(
            question: question,
            answer: answer,
            tags: tags,
            dueAt: due,
            sourceSpan: sourceSpan(noteID: note.id, cardOrd: 0)
        )
    }

    // MARK: - Private

    private static func isBasic(_ model: AnkiModel) -> Bool {
        guard model.type == 0 else { return false }
        let lower = model.fieldNames.map { $0.lowercased() }
        return lower.contains("front") && lower.contains("back")
    }

    private static func resolvedDue(note: AnkiNote, collectionCreatedAt: Date, importedAt: Date) -> Date {
        let effectiveDue = note.odid != 0 ? note.odue : note.due
        switch note.cardType {
        case 1, 3:   // learning / relearning — seconds timestamp
            return Date(timeIntervalSince1970: Double(effectiveDue))
        case 2:      // review — days since collection creation
            return collectionCreatedAt.addingTimeInterval(Double(effectiveDue) * 86_400)
        default:     // new (type 0) — import as due immediately
            return importedAt
        }
    }
}
