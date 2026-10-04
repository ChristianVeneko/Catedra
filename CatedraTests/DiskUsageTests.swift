import Testing
import Foundation
@testable import Catedra

struct DiskUsageSummaryTests {
    @Test func totalsAndSortsDescending() {
        let summary = DiskUsageSummary(entries: [
            CourseDiskUsage(folder: "03 - Fisica", bytes: 100),
            CourseDiskUsage(folder: "08 - Teoria de Control II", bytes: 900),
            CourseDiskUsage(folder: "01 - Algebra", bytes: 100),
        ])
        #expect(summary.total == 1_100)
        #expect(summary.entries.map(\.folder) == ["08 - Teoria de Control II", "01 - Algebra", "03 - Fisica"])
    }

    @Test func emptyIsZero() {
        let summary = DiskUsageSummary(entries: [])
        #expect(summary.total == 0)
        #expect(summary.entries.isEmpty)
    }

    @Test func displayNameStripsTheCourseNumber() {
        #expect(CourseDiskUsage(folder: "08 - Teoria de Control II", bytes: 1).displayName == "Teoria de Control II")
        #expect(CourseDiskUsage(folder: "misc", bytes: 1).displayName == "misc")
    }
}

struct FileSystemDiskScannerTests {
    @Test func measuresEachCourseFolderAndIgnoresOthers() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fm = FileManager.default
        let a = root.appendingPathComponent("01 - Algebra/contenidos", isDirectory: true)
        let b = root.appendingPathComponent("02 - Fisica", isDirectory: true)
        try fm.createDirectory(at: a, withIntermediateDirectories: true)
        try fm.createDirectory(at: b, withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("_sistema"), withIntermediateDirectories: true)
        try Data(count: 200_000).write(to: a.appendingPathComponent("big.bin"))
        try Data(count: 10).write(to: b.appendingPathComponent("tiny.bin"))
        try Data(count: 50_000).write(to: root.appendingPathComponent("_sistema/ignored.bin"))

        let result = FileSystemDiskScanner().scan(root: root)
        #expect(Set(result.map(\.folder)) == ["01 - Algebra", "02 - Fisica"])
        let algebra = try #require(result.first { $0.folder == "01 - Algebra" })
        #expect(algebra.bytes >= 200_000)
        let fisica = try #require(result.first { $0.folder == "02 - Fisica" })
        #expect(fisica.bytes < algebra.bytes)
    }

    @Test func missingRootYieldsNothing() {
        let missing = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")
        #expect(FileSystemDiskScanner().scan(root: missing).isEmpty)
    }
}
