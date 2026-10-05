import Foundation
import SQLite3

enum SearchIndexError: Error, LocalizedError {
    case sqlite(String)

    var errorDescription: String? {
        switch self { case .sqlite(let message): "Índice de búsqueda: \(message)" }
    }
}

/// FTS5 index on the system SQLite. Tokenizer `unicode61 remove_diacritics 2` makes matching accent and case insensitive.
///
/// Tables: `files(path, modified, size)` tracks what is indexed; `chunks` (FTS5: `path` and `page` unindexed, `body`)
/// holds one row per PDF page or text file; `meta` stores the workspace root the index belongs to.
actor SQLiteSearchIndex: SearchIndexStoring {
    static let schemaVersion: Int32 = 1
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    /// `~/Library/Application Support/Catedra/search-index.sqlite`.
    static var defaultFile: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Catedra/search-index.sqlite")
    }

    nonisolated(unsafe) private var db: OpaquePointer?

    init(file: URL = SQLiteSearchIndex.defaultFile) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        var handle: OpaquePointer?
        guard sqlite3_open_v2(file.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let opened = handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "no se pudo abrir la base de datos"
            sqlite3_close(handle)
            throw SearchIndexError.sqlite(message)
        }
        db = opened
        do { try Self.prepareSchema(opened) } catch { sqlite3_close(opened); throw error }
    }

    deinit { sqlite3_close(db) }

    // MARK: - SearchIndexStoring

    func ensureRoot(_ root: String) throws {
        let current = try scalarText("SELECT value FROM meta WHERE key = 'root'")
        guard current != root else { return }
        try inTransaction {
            try execute("DELETE FROM chunks")
            try execute("DELETE FROM files")
            try run("INSERT OR REPLACE INTO meta(key, value) VALUES('root', ?)") { sqlite3_bind_text($0, 1, root, -1, Self.transient) }
        }
    }

    func stamps() throws -> [String: FileStamp] {
        var result: [String: FileStamp] = [:]
        try query("SELECT path, modified, size FROM files", bind: { _ in }) { stmt in
            result[String(cString: sqlite3_column_text(stmt, 0))] = FileStamp(modified: sqlite3_column_int64(stmt, 1),
                                                                               size: sqlite3_column_int64(stmt, 2))
        }
        return result
    }

    func replace(path: String, stamp: FileStamp, pages: [IndexedPage]) throws {
        try inTransaction {
            try deleteRows(path: path)
            try run("INSERT INTO files(path, modified, size) VALUES(?, ?, ?)") {
                sqlite3_bind_text($0, 1, path, -1, Self.transient)
                sqlite3_bind_int64($0, 2, stamp.modified)
                sqlite3_bind_int64($0, 3, stamp.size)
            }
            for page in pages {
                try run("INSERT INTO chunks(path, page, body) VALUES(?, ?, ?)") {
                    sqlite3_bind_text($0, 1, path, -1, Self.transient)
                    sqlite3_bind_int($0, 2, Int32(page.page))
                    sqlite3_bind_text($0, 3, page.text.precomposedStringWithCanonicalMapping, -1, Self.transient)
                }
            }
        }
    }

    func remove(paths: [String]) throws {
        guard !paths.isEmpty else { return }
        try inTransaction { for path in paths { try deleteRows(path: path) } }
    }

    func search(match: String, limit: Int) throws -> [RawSearchHit] {
        var hits: [RawSearchHit] = []
        let sql = """
            SELECT path, page, snippet(chunks, 2, char(1), char(2), '…', 16)
            FROM chunks WHERE chunks MATCH ? ORDER BY rank LIMIT ?
            """
        try query(sql, bind: {
            sqlite3_bind_text($0, 1, match, -1, Self.transient)
            sqlite3_bind_int($0, 2, Int32(limit))
        }) { stmt in
            hits.append(RawSearchHit(path: String(cString: sqlite3_column_text(stmt, 0)), page: Int(sqlite3_column_int(stmt, 1)),
                                     snippet: String(cString: sqlite3_column_text(stmt, 2))))
        }
        return hits
    }

    // MARK: - SQLite helpers

    private static func prepareSchema(_ db: OpaquePointer) throws {
        func exec(_ sql: String) throws {
            var error: UnsafeMutablePointer<CChar>?
            guard sqlite3_exec(db, sql, nil, nil, &error) == SQLITE_OK else {
                let message = error.map { String(cString: $0) } ?? "error desconocido"
                sqlite3_free(error)
                throw SearchIndexError.sqlite(message)
            }
        }
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &stmt, nil)
        let version = sqlite3_step(stmt) == SQLITE_ROW ? sqlite3_column_int(stmt, 0) : 0
        sqlite3_finalize(stmt)
        if version != schemaVersion {
            try exec("DROP TABLE IF EXISTS chunks; DROP TABLE IF EXISTS files; DROP TABLE IF EXISTS meta;")
        }
        try exec("""
            CREATE TABLE IF NOT EXISTS files(path TEXT PRIMARY KEY, modified INTEGER NOT NULL, size INTEGER NOT NULL);
            CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY, value TEXT NOT NULL);
            CREATE VIRTUAL TABLE IF NOT EXISTS chunks USING fts5(
                path UNINDEXED, page UNINDEXED, body, tokenize = 'unicode61 remove_diacritics 2');
            PRAGMA user_version = \(schemaVersion);
            """)
        try exec("PRAGMA journal_mode = WAL; PRAGMA synchronous = NORMAL;")
    }

    private var lastError: String { db.map { String(cString: sqlite3_errmsg($0)) } ?? "base de datos cerrada" }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw SearchIndexError.sqlite(lastError) }
    }

    private func inTransaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do { try body(); try execute("COMMIT") } catch { try? execute("ROLLBACK"); throw error }
    }

    private func deleteRows(path: String) throws {
        try run("DELETE FROM chunks WHERE path = ?") { sqlite3_bind_text($0, 1, path, -1, Self.transient) }
        try run("DELETE FROM files WHERE path = ?") { sqlite3_bind_text($0, 1, path, -1, Self.transient) }
    }

    private func run(_ sql: String, bind: (OpaquePointer?) -> Void) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw SearchIndexError.sqlite(lastError) }
        defer { sqlite3_finalize(stmt) }
        bind(stmt)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw SearchIndexError.sqlite(lastError) }
    }

    private func query(_ sql: String, bind: (OpaquePointer?) -> Void, row: (OpaquePointer?) -> Void) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw SearchIndexError.sqlite(lastError) }
        defer { sqlite3_finalize(stmt) }
        bind(stmt)
        while true {
            switch sqlite3_step(stmt) {
            case SQLITE_ROW: row(stmt)
            case SQLITE_DONE: return
            default: throw SearchIndexError.sqlite(lastError)
            }
        }
    }

    private func scalarText(_ sql: String) throws -> String? {
        var value: String?
        try query(sql, bind: { _ in }) { value = sqlite3_column_text($0, 0).map { String(cString: $0) } }
        return value
    }
}
