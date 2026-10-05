import Foundation

/// Persistent full-text index (path + stamp + text per file or page).
protocol SearchIndexStoring: Sendable {
    /// Clears the index when it was built for another workspace root.
    func ensureRoot(_ root: String) async throws
    func stamps() async throws -> [String: FileStamp]
    /// Atomically replaces everything stored for `path`.
    func replace(path: String, stamp: FileStamp, pages: [IndexedPage]) async throws
    func remove(paths: [String]) async throws
    /// `match` must come from `SearchQuerySanitizer`.
    func search(match: String, limit: Int) async throws -> [RawSearchHit]
}

/// Lists the indexable files of the workspace with their stamps, keyed by workspace-relative path.
protocol ContentFileScanning: Sendable {
    func scan(root: URL, courses: [Course]) -> [String: FileStamp]
}

/// Extracts searchable text: one page per PDF page, a single page (0) for text files.
protocol ContentTextExtracting: Sendable {
    func pages(at url: URL, kind: IndexedFileKind) -> [IndexedPage]
}
