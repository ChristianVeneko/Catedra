import Testing
import Foundation
@testable import Catedra

struct SyncScriptInstallerTests {
    private func makeBundled(_ text: String = "print('v2')\n") throws -> URL {
        let dir = try makeTempDirectory()
        let url = dir.appendingPathComponent("sync_moodle.py")
        try Data(text.utf8).write(to: url)
        return url
    }

    private func installer(_ bundled: URL, date: Date = Date(timeIntervalSince1970: 1_700_000_000)) -> SyncScriptInstaller {
        SyncScriptInstaller(bundledScript: bundled, now: { date })
    }

    @Test func installsIntoFreshWorkspaceAndCreatesDataFolder() throws {
        let ws = try makeTempDirectory()
        let result = try installer(try makeBundled()).install(workspace: ws)
        #expect(result.action == .installed)
        #expect(try String(contentsOf: result.scriptURL, encoding: .utf8) == "print('v2')\n")
        #expect(result.scriptURL.path == ws.appendingPathComponent("_sistema/sync_moodle.py").path)
        var isDir: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: ws.appendingPathComponent("_sistema/data").path, isDirectory: &isDir) && isDir.boolValue)
    }

    @Test func leavesIdenticalScriptUntouched() throws {
        let ws = try makeTempDirectory()
        let sut = installer(try makeBundled())
        _ = try sut.install(workspace: ws)
        let result = try sut.install(workspace: ws)
        #expect(result.action == .unchanged)
        let files = try FileManager.default.contentsOfDirectory(atPath: ws.appendingPathComponent("_sistema").path)
        #expect(files.filter { $0.contains(".bak-") }.isEmpty)
    }

    @Test func backsUpADifferentScriptOnceBeforeOverwriting() throws {
        let ws = try makeTempDirectory()
        let sistema = ws.appendingPathComponent("_sistema", isDirectory: true)
        try FileManager.default.createDirectory(at: sistema, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: sistema.appendingPathComponent("sync_moodle.py"))
        let sut = installer(try makeBundled())
        let first = try sut.install(workspace: ws)
        guard case .updated(let backup) = first.action else { Issue.record("expected update"); return }
        #expect(backup.lastPathComponent.hasPrefix("sync_moodle.py.bak-"))
        #expect(try String(contentsOf: backup, encoding: .utf8) == "old")
        #expect(try String(contentsOf: first.scriptURL, encoding: .utf8) == "print('v2')\n")
        // A second run changes nothing and creates no further backup.
        #expect(try sut.install(workspace: ws).action == .unchanged)
        let backups = try FileManager.default.contentsOfDirectory(atPath: sistema.path).filter { $0.contains(".bak-") }
        #expect(backups.count == 1)
    }

    @Test func backupNameUsesTimestampFormat() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let name = SyncScriptInstaller.backupName(at: date, timeZone: TimeZone(identifier: "UTC")!)
        #expect(name == "sync_moodle.py.bak-20231114-221320")
    }

    @Test func existingBackupIsNeverOverwritten() throws {
        let ws = try makeTempDirectory()
        let sistema = ws.appendingPathComponent("_sistema", isDirectory: true)
        try FileManager.default.createDirectory(at: sistema, withIntermediateDirectories: true)
        let name = SyncScriptInstaller.backupName(at: Date(timeIntervalSince1970: 1_700_000_000))
        try Data("older backup".utf8).write(to: sistema.appendingPathComponent(name))
        try Data("old".utf8).write(to: sistema.appendingPathComponent("sync_moodle.py"))
        let result = try installer(try makeBundled()).install(workspace: ws)
        guard case .updated(let backup) = result.action else { Issue.record("expected update"); return }
        #expect(backup.lastPathComponent != name)
        #expect(try String(contentsOf: sistema.appendingPathComponent(name), encoding: .utf8) == "older backup")
    }

    @Test func missingBundledScriptThrows() throws {
        let ws = try makeTempDirectory()
        let sut = SyncScriptInstaller(bundledScript: URL(fileURLWithPath: "/nonexistent/sync_moodle.py"))
        #expect(throws: SyncScriptInstallError.self) { try sut.install(workspace: ws) }
    }
}
