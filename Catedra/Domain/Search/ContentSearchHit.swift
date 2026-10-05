import Foundation

/// Text of one PDF page (1-based) or of a whole text file (`page` 0).
struct IndexedPage: Equatable, Sendable {
    let page: Int
    let text: String
}

/// A row as returned by the index: workspace-relative path, page (0 = not paged) and the marked snippet.
struct RawSearchHit: Equatable, Sendable {
    let path: String
    let page: Int
    let snippet: String
}

struct IndexingReport: Equatable, Sendable {
    let added: Int
    let changed: Int
    let removed: Int
}

/// A full-text result resolved against the workspace.
struct ContentSearchHit: Identifiable, Equatable, Sendable {
    let relativePath: String
    let url: URL
    let courseFolder: String
    /// 1-based PDF page; nil for text files.
    let page: Int?
    /// Snippet with `SnippetParser` match markers.
    let snippet: String

    var id: String { "\(relativePath)#\(page ?? 0)" }
    var fileName: String { url.lastPathComponent }

    init(raw: RawSearchHit, root: URL) {
        relativePath = raw.path
        url = root.appendingPathComponent(raw.path)
        courseFolder = raw.path.split(separator: "/").first.map(String.init) ?? ""
        page = raw.page > 0 ? raw.page : nil
        snippet = raw.snippet
    }

    /// Keeps the order, at most `perFile` rows per file and `total` rows overall.
    static func diversified(_ hits: [ContentSearchHit], perFile: Int, total: Int) -> [ContentSearchHit] {
        var counts: [String: Int] = [:]
        var result: [ContentSearchHit] = []
        for hit in hits where result.count < total {
            guard counts[hit.relativePath, default: 0] < perFile else { continue }
            counts[hit.relativePath, default: 0] += 1
            result.append(hit)
        }
        return result
    }

    /// Unique files (in rank order, at most `maxFiles`) and the course whose agent should receive them: the course with
    /// most of those files, ties going to the first one found.
    static func attachmentTarget(for hits: [ContentSearchHit], maxFiles: Int) -> (courseFolder: String, files: [URL])? {
        var seen: Set<String> = []
        var picked: [ContentSearchHit] = []
        for hit in hits where picked.count < maxFiles && seen.insert(hit.relativePath).inserted { picked.append(hit) }
        guard let first = picked.first else { return nil }
        var counts: [String: Int] = [:]
        for hit in picked { counts[hit.courseFolder, default: 0] += 1 }
        let best = counts.values.max() ?? 0
        let course = picked.first { counts[$0.courseFolder] == best }?.courseFolder ?? first.courseFolder
        return (course, picked.map(\.url))
    }
}

struct SnippetSegment: Equatable, Sendable {
    let text: String
    let isMatch: Bool
}

/// Splits an FTS5 snippet marked with control characters into plain and matched runs. Pure.
enum SnippetParser {
    static let open = "\u{1}"
    static let close = "\u{2}"

    static func segments(from raw: String) -> [SnippetSegment] {
        var result: [SnippetSegment] = []
        var current = ""
        var inMatch = false
        func flush() {
            if !current.isEmpty { result.append(SnippetSegment(text: current, isMatch: inMatch)) }
            current = ""
        }
        for char in raw {
            if char.isNewline { current.append(" "); continue }
            switch String(char) {
            case open: flush(); inMatch = true
            case close: flush(); inMatch = false
            case "\t": current.append(" ")
            default: current.append(char)
            }
        }
        flush()
        return result
    }
}
