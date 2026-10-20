import Foundation

/// Finds teleprompter scripts in a scope's `apuntes/guiones/` folder for `/guion [nombre]`.
enum ScriptLocator {
    static let relativeFolder = "apuntes/guiones"

    /// Without a name, the most recently modified script. With a name, the newest script whose file name contains
    /// every word of it (ignoring case and accents).
    static func find(_ name: String?, in scopeFolder: URL) -> URL? {
        let folder = scopeFolder.appending(path: relativeFolder)
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys,
                                                                       options: [.skipsHiddenFiles]) else { return nil }
        var query = name ?? ""
        if query.lowercased().hasSuffix(".md") { query = String(query.dropLast(3)) }
        let wanted = words(query)
        return files
            .filter { $0.pathExtension.lowercased() == "md" }
            .filter { file in
                let stem = words(file.deletingPathExtension().lastPathComponent).joined(separator: " ")
                return wanted.allSatisfy { stem.contains($0) }
            }
            .max { modified($0) < modified($1) }
    }

    /// Same split for the typed name and the file name, so "resumen-ensayo" finds `resumen-ensayo.md`.
    private static func words(_ text: String) -> [String] {
        text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map { Script.normalize(String($0)) }.filter { !$0.isEmpty }
    }

    private static func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}
