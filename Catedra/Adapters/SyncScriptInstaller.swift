import Foundation
import CryptoKit

/// Keeps `<workspace>/_sistema/sync_moodle.py` identical to the script bundled in the app (SHA-256 comparison).
/// A different existing script is backed up once (`sync_moodle.py.bak-<yyyyMMdd-HHmmss>`) before it is replaced.
struct SyncScriptInstaller: SyncScriptInstalling {
    static let scriptName = "sync_moodle.py"

    var bundledScript: URL
    var now: @Sendable () -> Date = { Date() }

    /// Installer for the script shipped inside the app bundle; nil if the bundle lacks it.
    static func bundled(in bundle: Bundle = .main) -> SyncScriptInstaller? {
        bundle.url(forResource: "sync_moodle", withExtension: "py").map { SyncScriptInstaller(bundledScript: $0) }
    }

    static func backupName(at date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "\(scriptName).bak-\(formatter.string(from: date))"
    }

    func install(workspace: URL) throws -> SyncScriptInstallResult {
        let fm = FileManager.default
        guard let bundledData = try? Data(contentsOf: bundledScript) else { throw SyncScriptInstallError.bundledScriptMissing }
        let sistema = workspace.appendingPathComponent("_sistema", isDirectory: true)
        do {
            try fm.createDirectory(at: sistema.appendingPathComponent("data", isDirectory: true), withIntermediateDirectories: true)
            let target = sistema.appendingPathComponent(Self.scriptName)
            guard fm.fileExists(atPath: target.path) else {
                try write(bundledData, to: target)
                return SyncScriptInstallResult(scriptURL: target, action: .installed)
            }
            if let existing = try? Data(contentsOf: target), Self.sha256(existing) == Self.sha256(bundledData) {
                return SyncScriptInstallResult(scriptURL: target, action: .unchanged)
            }
            let backup = uniqueBackupURL(in: sistema)
            try fm.copyItem(at: target, to: backup)
            try write(bundledData, to: target)
            return SyncScriptInstallResult(scriptURL: target, action: .updated(backup: backup))
        } catch let error as SyncScriptInstallError {
            throw error
        } catch {
            throw SyncScriptInstallError.writeFailed(error.localizedDescription)
        }
    }

    private func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }

    private func uniqueBackupURL(in folder: URL) -> URL {
        let base = Self.backupName(at: now())
        var candidate = folder.appendingPathComponent(base)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base)-\(counter)")
            counter += 1
        }
        return candidate
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
