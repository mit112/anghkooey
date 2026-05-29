import Foundation
import SQLite3

// Row accessor wrapping a live sqlite3_stmt pointer.
// Only valid inside the query closure — do not escape.
struct SQLiteRow {
    private let stmt: OpaquePointer

    init(_ stmt: OpaquePointer) { self.stmt = stmt }

    func int(_ col: Int32) -> Int { Int(sqlite3_column_int64(stmt, col)) }
    func text(_ col: Int32) -> String {
        guard let ptr = sqlite3_column_text(stmt, col) else { return "" }
        return String(cString: ptr)
    }
}

final class SQLiteReader {
    private var db: OpaquePointer?

    init(url: URL) throws {
        let code = sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil)
        guard code == SQLITE_OK else {
            sqlite3_close(db)
            throw AnkiImportError.databaseCorrupted
        }
    }

    deinit { sqlite3_close(db) }

    func query(_ sql: String, _ handler: (SQLiteRow) throws -> Void) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw AnkiImportError.databaseCorrupted
        }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let s = stmt else { break }
            try handler(SQLiteRow(s))
        }
    }
}
