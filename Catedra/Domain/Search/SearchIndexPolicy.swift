import Foundation

enum IndexedFileKind: Sendable, Equatable { case pdf, text }

/// Decides which files of the workspace enter the full-text index. Pure.
enum SearchIndexPolicy {
    /// Generated or system folders that are never indexed.
    static let excludedFolderNames: Set<String> = ["_sistema", "_imagenes"]
    static let maxPDFBytes: Int64 = 150_000_000
    static let maxTextBytes: Int64 = 5_000_000

    /// Kind of a workspace-relative path, or nil when the file must not be indexed.
    static func kind(forRelativePath path: String) -> IndexedFileKind? {
        let components = path.split(separator: "/").map(String.init)
        guard let name = components.last else { return nil }
        guard components.dropLast().allSatisfy({ shouldDescend(into: $0) }) else { return nil }
        guard !name.hasPrefix(".") else { return nil }
        switch (name as NSString).pathExtension.lowercased() {
        case "pdf": return .pdf
        case "md", "txt": return .text
        default: return nil
        }
    }

    static func shouldDescend(into folderName: String) -> Bool {
        !folderName.hasPrefix(".") && !excludedFolderNames.contains(folderName)
    }

    static func isWithinSizeLimit(_ kind: IndexedFileKind, bytes: Int64) -> Bool {
        bytes <= (kind == .pdf ? maxPDFBytes : maxTextBytes)
    }
}
