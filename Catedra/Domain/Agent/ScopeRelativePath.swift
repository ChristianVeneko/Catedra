import Foundation

/// Builds `@path` references for attached files: relative inside a scope folder, absolute anywhere else.
enum ScopeRelativePath {
    /// `@relative/path` (quoted when it has spaces), or nil when the file is not strictly inside `base`.
    static func reference(for file: URL, in base: URL) -> String? {
        let basePath = base.standardizedFileURL.resolvingSymlinksInPath().path
        let filePath = file.standardizedFileURL.resolvingSymlinksInPath().path
        let prefix = basePath.hasSuffix("/") ? basePath : basePath + "/"
        guard filePath.hasPrefix(prefix), filePath.count > prefix.count else { return nil }
        let relative = String(filePath.dropFirst(prefix.count))
        return quoted(relative)
    }

    /// `@relative/path` inside `base`, otherwise `@/absolute/path` (quoted when it has spaces).
    static func attachment(for file: URL, in base: URL) -> String {
        if let relative = reference(for: file, in: base) { return relative }
        return quoted(file.standardizedFileURL.path)
    }

    /// `@"path"` when the path has spaces, `@path` otherwise.
    static func quoted(_ path: String) -> String { path.contains(" ") ? "@\"\(path)\"" : "@\(path)" }

    private static let absoluteReference = try! NSRegularExpression(pattern: #"(?<!\S)@(?:"(/[^"]+)"|(/\S+))"#)

    /// Absolute paths referenced as `@/path` or `@"/path with spaces"` in a prompt, in order of appearance.
    static func absolutePaths(in prompt: String) -> [String] {
        let ns = prompt as NSString
        return absoluteReference.matches(in: prompt, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            for group in 1...2 where match.range(at: group).location != NSNotFound { return ns.substring(with: match.range(at: group)) }
            return nil
        }
    }

    /// Parent folders of absolute references that lie outside `cwd`, deduplicated, in order of appearance.
    static func extraDirectories(in prompt: String, cwd: URL) -> [String] {
        let base = cwd.standardizedFileURL.resolvingSymlinksInPath().path
        var seen: Set<String> = []
        var result: [String] = []
        for path in absolutePaths(in: prompt) {
            let file = URL(fileURLWithPath: path).standardizedFileURL
            let resolved = file.resolvingSymlinksInPath().path
            guard resolved != base, !resolved.hasPrefix(base + "/") else { continue }
            let directory = file.deletingLastPathComponent().path
            if seen.insert(directory).inserted { result.append(directory) }
        }
        return result
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
