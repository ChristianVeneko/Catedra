import Foundation

struct SyncLogLine: Identifiable, Sendable, Equatable {
    let id = UUID()
    let text: String
    let isError: Bool
    let event: SyncLogEvent
}

enum SyncOutcome: Sendable, Equatable {
    case success(ActivityDiff)
    case loginFailed(String)
    case missingCredentials
    case missingPython
    case installFailed(String)
    case failed(exitCode: Int32)
}

enum SyncProgress: Sendable {
    case log(SyncLogLine)
    case finished(SyncOutcome)
}

struct SyncUseCase: Sendable {
    let syncer: MoodleSyncing
    let credentials: CredentialStoring
    let reader: WorkspaceReading
    /// Installs the bundled script into the workspace before every run; nil skips the step.
    var installer: SyncScriptInstalling?

    func execute(root: URL, pythonPath: String, includeFiles: Bool) -> AsyncStream<SyncProgress> {
        AsyncStream { continuation in
            let task = Task {
                guard let creds = credentials.load(), !creds.username.isEmpty, !creds.password.isEmpty else {
                    continuation.yield(.finished(.missingCredentials)); continuation.finish(); return
                }
                guard !pythonPath.isEmpty, FileManager.default.isExecutableFile(atPath: pythonPath) else {
                    continuation.yield(.finished(.missingPython)); continuation.finish(); return
                }
                if let installer {
                    do { _ = try installer.install(workspace: root) } catch {
                        continuation.yield(.finished(.installFailed(error.localizedDescription))); continuation.finish(); return
                    }
                }
                let before = (try? reader.loadSnapshot(root: root))?.activities ?? []
                let config = SyncConfiguration(workspaceRoot: root, pythonPath: pythonPath, username: creds.username,
                                               password: creds.password, includeFiles: includeFiles)
                var loginError: String?
                var outcome: SyncOutcome = .failed(exitCode: -1)
                for await output in syncer.run(config) {
                    switch output {
                    case .line(let text, let isError):
                        let event = SyncLogParser.parse(text, isError: isError)
                        if case .loginFailed(let detail) = event { loginError = detail }
                        if event != .ignored {
                            continuation.yield(.log(SyncLogLine(text: text, isError: isError, event: event)))
                        }
                    case .finished(let code):
                        if let loginError { outcome = .loginFailed(loginError) }
                        else if code == 0 {
                            let after = (try? reader.loadSnapshot(root: root))?.activities ?? []
                            outcome = .success(ActivityDiff.compare(before: before, after: after))
                        } else { outcome = .failed(exitCode: code) }
                    }
                }
                continuation.yield(.finished(outcome))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
