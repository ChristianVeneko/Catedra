import Foundation

/// Walks every course folder and keeps the files `SearchIndexPolicy` accepts.
struct FileSystemContentScanner: ContentFileScanning {
    func scan(root: URL, courses: [Course]) -> [String: FileStamp] {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey, .isSymbolicLinkKey]
        var result: [String: FileStamp] = [:]
        let rootPath = root.standardizedFileURL.path
        for course in courses {
            let base = root.appendingPathComponent(course.folderName, isDirectory: true)
            guard let walker = fm.enumerator(at: base, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in walker {
                guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isSymbolicLink != true else { continue }
                if values.isDirectory == true {
                    if !SearchIndexPolicy.shouldDescend(into: url.lastPathComponent) { walker.skipDescendants() }
                    continue
                }
                let full = url.standardizedFileURL.path
                guard full.hasPrefix(rootPath + "/") else { continue }
                let relative = String(full.dropFirst(rootPath.count + 1))
                guard let kind = SearchIndexPolicy.kind(forRelativePath: relative) else { continue }
                let size = Int64(values.fileSize ?? 0)
                guard SearchIndexPolicy.isWithinSizeLimit(kind, bytes: size) else { continue }
                let modified = Int64(((values.contentModificationDate ?? .distantPast).timeIntervalSince1970 * 1000).rounded())
                result[relative] = FileStamp(modified: modified, size: size)
            }
        }
        return result
    }
}
