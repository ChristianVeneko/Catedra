import Foundation

/// Builds `@path` references for files inside a scope folder.
enum ScopeRelativePath {
    /// `@relative/path` (quoted when it has spaces), or nil when the file is not strictly inside `base`.
    static func reference(for file: URL, in base: URL) -> String? {
        let basePath = base.standardizedFileURL.resolvingSymlinksInPath().path
        let filePath = file.standardizedFileURL.resolvingSymlinksInPath().path
        let prefix = basePath.hasSuffix("/") ? basePath : basePath + "/"
        guard filePath.hasPrefix(prefix), filePath.count > prefix.count else { return nil }
        let relative = String(filePath.dropFirst(prefix.count))
        return relative.contains(" ") ? "@\"\(relative)\"" : "@\(relative)"
    }

    /// Inserts references at `caret` (UTF-16), separated by single spaces, and reports the new caret.
    static func insert(_ references: [String], into text: String, at caret: Int) -> (text: String, caret: Int) {
        let ns = text as NSString
        let at = min(max(caret, 0), ns.length)
        var insertion = references.joined(separator: " ") + " "
        if at > 0, let scalar = Unicode.Scalar(ns.character(at: at - 1)), !CharacterSet.whitespacesAndNewlines.contains(scalar) {
            insertion = " " + insertion
        }
        return (ns.replacingCharacters(in: NSRange(location: at, length: 0), with: insertion), at + (insertion as NSString).length)
    }
}
