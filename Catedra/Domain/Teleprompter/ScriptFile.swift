import Foundation

/// Which Markdown files are teleprompter scripts: any `.md` inside a `guiones/` folder, or with `tipo: guion` in its
/// frontmatter. Scripts stay plain Markdown so previews, Obsidian and editors keep working; the app only marks them.
enum ScriptFile {
    static func isScript(path: String, head: String?) -> Bool {
        let url = URL(fileURLWithPath: path)
        guard url.pathExtension.lowercased() == "md" else { return false }
        if url.deletingLastPathComponent().pathComponents.contains(where: { $0.lowercased() == "guiones" }) { return true }
        guard let head else { return false }
        return frontmatterType(head) == "guion"
    }

    /// Reads only the beginning of the file (frontmatter is at the top).
    static func isScript(_ url: URL) -> Bool {
        guard url.pathExtension.lowercased() == "md" else { return false }
        if isScript(path: url.path, head: nil) { return true }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: 1024)) ?? Data()
        return isScript(path: url.path, head: String(decoding: data, as: UTF8.self))
    }

    private static func frontmatterType(_ head: String) -> String? {
        let lines = head.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        guard lines.first == "---" else { return nil }
        for line in lines.dropFirst() {
            if line == "---" { return nil }
            guard let colon = line.firstIndex(of: ":"), line[..<colon].lowercased() == "tipo" else { continue }
            let value = line[line.index(after: colon)...].trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
            return Script.normalize(value)
        }
        return nil
    }
}
