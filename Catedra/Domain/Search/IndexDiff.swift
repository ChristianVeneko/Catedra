import Foundation

/// Modification time (milliseconds since 1970) and size: a file counts as changed when either differs.
struct FileStamp: Hashable, Sendable {
    let modified: Int64
    let size: Int64
}

/// What an incremental run has to do, comparing the stored stamps with what is on disk. Pure.
struct IndexDiff: Equatable, Sendable {
    let added: [String]
    let changed: [String]
    let removed: [String]

    var toIndex: [String] { (added + changed).sorted() }
    var isEmpty: Bool { added.isEmpty && changed.isEmpty && removed.isEmpty }

    static func compute(stored: [String: FileStamp], current: [String: FileStamp]) -> IndexDiff {
        var added: [String] = [], changed: [String] = []
        for (path, stamp) in current {
            guard let old = stored[path] else { added.append(path); continue }
            if old != stamp { changed.append(path) }
        }
        let removed = stored.keys.filter { current[$0] == nil }
        return IndexDiff(added: added.sorted(), changed: changed.sorted(), removed: removed.sorted())
    }
}
