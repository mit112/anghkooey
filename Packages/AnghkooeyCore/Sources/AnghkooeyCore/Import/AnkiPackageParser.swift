import Foundation
import ZIPFoundation

// MARK: - Internal data types

struct AnkiNote {
    let id: Int
    let modelID: Int
    let fields: [String]   // notes.flds split on \x1f, in field order
    let deckID: Int
    let cardType: Int      // cards.type: 0=new,1=learning,2=review,3=relearning
    let due: Int           // cards.due
    let odue: Int          // cards.odue (filtered deck real due)
    let odid: Int          // cards.odid (non-zero = filtered deck)
}

struct AnkiModel {
    let id: Int
    let type: Int          // 0=standard,1=cloze
    let fieldNames: [String]
}

struct AnkiCollection {
    let createdAt: Date
    let models: [Int: AnkiModel]
    let deckNames: [Int: String]
    let notes: [AnkiNote]
}

// MARK: - JSON shapes for col.models and col.decks

private struct RawModel: Decodable {
    let id: Int
    let type: Int
    let flds: [RawField]
    struct RawField: Decodable { let name: String }
}

private struct RawDeck: Decodable {
    let id: Int
    let name: String
}

// MARK: - Parser

enum AnkiPackageParser {

    /// Extracts and parses an .apkg archive. Returns the full collection.
    /// Throws `AnkiImportError` on any failure.
    static func parse(apkgURL: URL) throws -> AnkiCollection {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("anghkooey-import-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let dbURL = try extractDatabase(from: apkgURL, into: tmpDir)
        return try parseDatabase(at: dbURL)
    }

    // MARK: - Extraction

    private static func extractDatabase(from apkgURL: URL, into dir: URL) throws -> URL {
        let archive: Archive
        do {
            archive = try Archive(url: apkgURL, accessMode: .read)
        } catch {
            throw AnkiImportError.corruptedArchive
        }

        // .anki21b uses zstd — not supported; direct user to legacy export.
        if archive["collection.anki21b"] != nil {
            throw AnkiImportError.corruptedArchive
        }

        let candidates = ["collection.anki21", "collection.anki2"]
        var foundEntry: Entry?
        for candidate in candidates {
            if let entry = archive[candidate] { foundEntry = entry; break }
        }
        guard let entry = foundEntry else {
            throw AnkiImportError.notAnApkgFile
        }

        let destURL = dir.appendingPathComponent("collection.anki2")
        do {
            _ = try archive.extract(entry, to: destURL)
        } catch {
            throw AnkiImportError.corruptedArchive
        }
        return destURL
    }

    // MARK: - Database parsing

    private static func parseDatabase(at dbURL: URL) throws -> AnkiCollection {
        let db = try SQLiteReader(url: dbURL)

        var createdAt = Date.now
        var modelsJSON = ""
        var decksJSON = ""

        try db.query("SELECT crt, models, decks FROM col LIMIT 1") { row in
            createdAt = Date(timeIntervalSince1970: Double(row.int(0)))
            modelsJSON = row.text(1)
            decksJSON = row.text(2)
        }

        let models = try parseModels(json: modelsJSON)
        let deckNames = try parseDeckNames(json: decksJSON)
        let notes = try parseNotes(db: db)

        return AnkiCollection(
            createdAt: createdAt,
            models: models,
            deckNames: deckNames,
            notes: notes
        )
    }

    private static func parseModels(json: String) throws -> [Int: AnkiModel] {
        guard let data = json.data(using: .utf8),
              let raw = try? JSONDecoder().decode([String: RawModel].self, from: data)
        else { throw AnkiImportError.databaseCorrupted }

        return Dictionary(uniqueKeysWithValues: raw.values.map { m in
            (m.id, AnkiModel(id: m.id, type: m.type, fieldNames: m.flds.map(\.name)))
        })
    }

    private static func parseDeckNames(json: String) throws -> [Int: String] {
        guard let data = json.data(using: .utf8),
              let raw = try? JSONDecoder().decode([String: RawDeck].self, from: data)
        else { throw AnkiImportError.databaseCorrupted }

        return Dictionary(uniqueKeysWithValues: raw.values.map { ($0.id, $0.name) })
    }

    private static func parseNotes(db: SQLiteReader) throws -> [AnkiNote] {
        var notes: [AnkiNote] = []
        let sql = """
            SELECT n.id, n.mid, n.flds,
                   c.did, c.odid, c.type, c.due, c.odue
            FROM notes n
            JOIN cards c ON c.nid = n.id
            """
        try db.query(sql) { row in
            let fields = row.text(2).components(separatedBy: "\u{001F}")
            notes.append(AnkiNote(
                id: row.int(0),
                modelID: row.int(1),
                fields: fields,
                deckID: row.int(3),
                cardType: row.int(5),
                due: row.int(6),
                odue: row.int(7),
                odid: row.int(4)
            ))
        }
        return notes
    }
}
