import Testing
import Foundation
@testable import Catedra

struct GeneratedFilesScannerTests {
    @Test func returnsOnlyVisibleFilesNewerThanStart() throws {
        let dir = try makeTempDirectory()
        let fm = FileManager.default
        let start = Date()
        let old = dir.appendingPathComponent("old.md")
        let new = dir.appendingPathComponent("entrega/new.docx")
        let hidden = dir.appendingPathComponent(".hidden.md")
        try fm.createDirectory(at: new.deletingLastPathComponent(), withIntermediateDirectories: true)
        for url in [old, new, hidden] { try "x".write(to: url, atomically: true, encoding: .utf8) }
        try fm.setAttributes([.modificationDate: start.addingTimeInterval(-3600)], ofItemAtPath: old.path)
        try fm.setAttributes([.modificationDate: start.addingTimeInterval(5)], ofItemAtPath: new.path)
        try fm.setAttributes([.modificationDate: start.addingTimeInterval(5)], ofItemAtPath: hidden.path)

        let found = GeneratedFilesScanner.scan(folder: dir, since: start)
        #expect(found.map(\.lastPathComponent) == ["new.docx"])
    }

    @Test func missingFolderYieldsEmpty() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("nope-\(UUID())")
        #expect(GeneratedFilesScanner.scan(folder: url, since: .distantPast).isEmpty)
    }

    @Test func respectsLimit() throws {
        let dir = try makeTempDirectory()
        for i in 0..<5 { try "x".write(to: dir.appendingPathComponent("f\(i).txt"), atomically: true, encoding: .utf8) }
        #expect(GeneratedFilesScanner.scan(folder: dir, since: .distantPast, limit: 2).count == 2)
    }
}
