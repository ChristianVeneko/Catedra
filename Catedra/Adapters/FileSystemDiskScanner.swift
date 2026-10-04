import Foundation

/// Walks each course folder of the workspace summing allocated sizes; unreadable entries are skipped.
struct FileSystemDiskScanner: DiskUsageScanning {
    func scan(root: URL) -> [CourseDiskUsage] {
        let fm = FileManager.default
        guard let folders = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey],
                                                        options: [.skipsHiddenFiles]) else { return [] }
        return folders.compactMap { url in
            guard Course(folderName: url.lastPathComponent) != nil,
                  (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
            return CourseDiskUsage(folder: url.lastPathComponent, bytes: size(of: url))
        }
    }

    private func size(of folder: URL) -> UInt64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys,
                                                          options: [], errorHandler: { _, _ in true }) else { return 0 }
        var total: UInt64 = 0
        for case let url as URL in walker {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            total += UInt64(values.totalFileAllocatedSize ?? 0)
        }
        return total
    }
}
