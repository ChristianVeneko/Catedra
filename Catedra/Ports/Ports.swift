import Foundation

protocol WorkspaceReading: Sendable {
    func loadSnapshot(root: URL) throws -> WorkspaceSnapshot
    func files(root: URL, activity: Activity) -> ActivityFiles
    func contentTree(root: URL, course: Course) -> [ContentNode]
    func forums(root: URL, course: Course) -> [ContentNode]
}

struct SyncConfiguration: Sendable {
    var workspaceRoot: URL
    var pythonPath: String
    var username: String
    var password: String
    var includeFiles: Bool
}

enum SyncOutput: Sendable, Equatable {
    case line(String, isError: Bool)
    case finished(exitCode: Int32)
}

protocol MoodleSyncing: Sendable {
    /// Runs the sync script and streams output. The stream ends after `.finished`.
    func run(_ configuration: SyncConfiguration) -> AsyncStream<SyncOutput>
}

struct SAIACredentials: Sendable, Equatable {
    var username: String
    var password: String
}

protocol CredentialStoring: Sendable {
    func load() -> SAIACredentials?
    func save(_ credentials: SAIACredentials) throws
    func delete() throws
}

protocol FileImporting: Sendable {
    func importFiles(_ sources: [URL], into target: ImportTarget, activityFolder: URL) throws -> [URL]
}

enum SyncScriptInstallAction: Sendable, Equatable {
    case installed
    case unchanged
    /// The previous, different script was copied to `backup` before being replaced.
    case updated(backup: URL)
}

struct SyncScriptInstallResult: Sendable, Equatable {
    var scriptURL: URL
    var action: SyncScriptInstallAction
}

enum SyncScriptInstallError: Error, Sendable, Equatable, LocalizedError {
    case bundledScriptMissing
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .bundledScriptMissing: "La aplicación no incluye el script de sincronización."
        case .writeFailed(let detail): "No se pudo instalar el script de sincronización: \(detail)"
        }
    }
}

/// Makes sure the workspace holds the sync script shipped with the app.
protocol SyncScriptInstalling: Sendable {
    func install(workspace: URL) throws -> SyncScriptInstallResult
}
