import Testing
import Foundation
@testable import Catedra

struct SyncUseCaseTests {
    struct FakeCredentials: CredentialStoring {
        func load() -> SAIACredentials? { SAIACredentials(username: "u", password: "p") }
        func save(_ credentials: SAIACredentials) throws {}
        func delete() throws {}
    }
    final class Recorder: @unchecked Sendable { var events: [String] = []; var config: SyncConfiguration? }
    struct FakeSyncer: MoodleSyncing {
        let recorder: Recorder
        func run(_ configuration: SyncConfiguration) -> AsyncStream<SyncOutput> {
            recorder.events.append("sync"); recorder.config = configuration
            return AsyncStream { $0.yield(.finished(exitCode: 0)); $0.finish() }
        }
    }
    struct FakeInstaller: SyncScriptInstalling {
        let recorder: Recorder
        var fail = false
        func install(workspace: URL) throws -> SyncScriptInstallResult {
            recorder.events.append("install")
            if fail { throw SyncScriptInstallError.bundledScriptMissing }
            return SyncScriptInstallResult(scriptURL: workspace, action: .unchanged)
        }
    }
    struct EmptyReader: WorkspaceReading {
        func loadSnapshot(root: URL) throws -> WorkspaceSnapshot { .empty }
        func files(root: URL, activity: Activity) -> ActivityFiles { ActivityFiles() }
        func contentTree(root: URL, course: Course) -> [ContentNode] { [] }
        func forums(root: URL, course: Course) -> [ContentNode] { [] }
    }

    private func outcome(_ useCase: SyncUseCase) async -> SyncOutcome? {
        var result: SyncOutcome?
        for await progress in useCase.execute(root: URL(fileURLWithPath: "/tmp/ws"), pythonPath: "/bin/sh", includeFiles: true) {
            if case .finished(let o) = progress { result = o }
        }
        return result
    }

    @Test func installsTheScriptBeforeSyncing() async {
        let recorder = Recorder()
        let useCase = SyncUseCase(syncer: FakeSyncer(recorder: recorder), credentials: FakeCredentials(), reader: EmptyReader(),
                                  installer: FakeInstaller(recorder: recorder))
        _ = await outcome(useCase)
        #expect(recorder.events == ["install", "sync"])
    }

    @Test func installFailureStopsTheSync() async {
        let recorder = Recorder()
        let useCase = SyncUseCase(syncer: FakeSyncer(recorder: recorder), credentials: FakeCredentials(), reader: EmptyReader(),
                                  installer: FakeInstaller(recorder: recorder, fail: true))
        let result = await outcome(useCase)
        #expect(recorder.events == ["install"])
        if case .installFailed? = result {} else { Issue.record("expected installFailed, got \(String(describing: result))") }
    }
}
