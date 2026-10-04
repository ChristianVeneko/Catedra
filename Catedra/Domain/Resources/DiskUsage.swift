import Foundation

struct CourseDiskUsage: Equatable, Identifiable, Sendable {
    let folder: String
    let bytes: UInt64

    var id: String { folder }
    var displayName: String { Course(folderName: folder)?.name ?? folder }
}

/// Per-course sizes sorted largest first (ties by folder name) plus the total.
struct DiskUsageSummary: Equatable, Sendable {
    let entries: [CourseDiskUsage]
    let total: UInt64

    init(entries: [CourseDiskUsage]) {
        self.entries = entries.sorted { ($0.bytes, $1.folder) > ($1.bytes, $0.folder) }
        self.total = entries.reduce(0) { $0 + $1.bytes }
    }
}
