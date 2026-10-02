import Testing
import Foundation
@testable import Catedra

@MainActor
struct OnboardingModelTests {
    struct FakeAuth: MoodleAuthChecking {
        var result: MoodleAuthResult = .success
        func check(username: String, password: String) async -> MoodleAuthResult { result }
    }
    struct FakeProbe: DependencyProbing {
        var table: [DependencyID: DependencyObservation] = [:]
        func observe(_ id: DependencyID, context: DependencyProbeContext) async -> DependencyObservation { table[id] ?? .notFound }
    }
    struct NoCommands: CommandStreaming {
        func run(_ executable: String, arguments: [String]) -> AsyncStream<SyncOutput> { AsyncStream { $0.finish() } }
    }
    final class FakeInstaller: SyncScriptInstalling, @unchecked Sendable {
        var installedInto: [URL] = []
        func install(workspace: URL) throws -> SyncScriptInstallResult {
            installedInto.append(workspace)
            return SyncScriptInstallResult(scriptURL: workspace, action: .installed)
        }
    }

    private static let healthy: [DependencyID: DependencyObservation] = [
        .python: .found(path: "/usr/bin/python3", output: "Python 3.12.1"),
        .requests: .found(path: "/usr/bin/python3", output: "2.32.0"),
        .agent(.claude): .found(path: "/bin/claude", output: "2.1.0"),
    ]

    private func makeModel(table: [DependencyID: DependencyObservation] = healthy, installer: FakeInstaller = FakeInstaller(),
                           home: String = "/Users/test") -> (OnboardingModel, SettingsModel, UserDefaults, FakeInstaller) {
        let suite = "catedra-onboarding-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = SettingsModel(store: EmptyCredentialStore(), defaults: defaults)
        let model = OnboardingModel(settings: settings, auth: FakeAuth(), probe: FakeProbe(table: table), commands: NoCommands(),
                                    installer: installer, defaults: defaults, home: home)
        return (model, settings, defaults, installer)
    }

    private func settle(_ model: OnboardingModel) async {
        model.recheck()
        for _ in 0..<200 where model.isChecking { try? await Task.sleep(for: .milliseconds(10)) }
    }

    // MARK: folder suggestion

    @Test func suggestsDocumentsFolderUnlessCurrentIsExplicitOrSynced() throws {
        let inspector = WorkspaceInspector()
        let empty = try makeTempDirectory()
        #expect(OnboardingModel.initialFolder(currentPath: empty.path, isExplicit: false, inspector: inspector, home: "/h") == "/h/Documents/Cátedra")
        #expect(OnboardingModel.initialFolder(currentPath: empty.path, isExplicit: true, inspector: inspector, home: "/h") == empty.path)
        let data = empty.appendingPathComponent("_sistema/data", isDirectory: true)
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        try Data("[]".utf8).write(to: data.appendingPathComponent("activities.json"))
        #expect(OnboardingModel.initialFolder(currentPath: empty.path, isExplicit: false, inspector: inspector, home: "/h") == empty.path)
    }

    @Test func folderStepRequiresAWritableFolder() async throws {
        let (model, _, _, _) = makeModel()
        model.next() // folder
        model.setFolder("/System/Library/not-writable-\(UUID().uuidString)")
        #expect(model.step == .folder)
        #expect(!model.canAdvance)
        model.setFolder(try makeTempDirectory().path)
        #expect(model.canAdvance)
        model.next()
        #expect(model.step == .credentials)
        model.back()
        #expect(model.step == .folder)
    }

    @Test func starterFilesAreOfferedOnlyForNewWorkspacesWithoutInstructions() throws {
        let (model, _, _, _) = makeModel()
        let fresh = try makeTempDirectory()
        model.setFolder(fresh.path)
        #expect(model.offersStarterFiles && model.createStarterFiles)
        try Data("x".utf8).write(to: fresh.appendingPathComponent("AGENTS.md"))
        model.setFolder(fresh.path)
        #expect(!model.offersStarterFiles && !model.createStarterFiles)
    }

    // MARK: dependencies

    @Test func checksFollowTheSelectedProvider() async {
        let (model, _, _, _) = makeModel()
        await settle(model)
        #expect(model.readiness == .ready)
        model.provider = .opencode
        #expect(model.readiness == .blocked([.agent(.opencode)]))
        #expect(model.check(for: .claude)?.requirement == .optional)
    }

    @Test func missingPythonBlocksReadiness() async {
        let (model, _, _, _) = makeModel(table: [.agent(.claude): .found(path: "/bin/claude", output: "1.0")])
        await settle(model)
        guard case .blocked(let ids) = model.readiness else { Issue.record("expected blocked"); return }
        #expect(ids.contains(.python))
        #expect(ids.contains(.requests))
    }

    // MARK: connection test

    @Test func connectionTestReportsTheResult() async {
        let (model, _, _, _) = makeModel()
        model.username = "u"; model.password = "p"
        model.testConnection()
        for _ in 0..<200 where model.authState == .testing || model.authState == .idle { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(model.authState == .finished(.success))
    }

    @Test func connectionTestNeedsBothFields() {
        let (model, _, _, _) = makeModel()
        model.username = "u"
        #expect(!model.canTestConnection)
    }

    // MARK: finish

    @Test func finishWritesSettingsFlagStarterFilesAndInstallsTheScript() async throws {
        let (model, settings, defaults, installer) = makeModel()
        await settle(model)
        let folder = try makeTempDirectory().appendingPathComponent("Cátedra")
        model.setFolder(folder.path)
        model.provider = .claude
        model.syncNow = false
        let ok = await model.finish()
        #expect(ok)
        #expect(settings.workspacePath == folder.path)
        #expect(settings.agentProvider == .claude)
        #expect(settings.pythonPath == "/usr/bin/python3")
        #expect(defaults.bool(forKey: "onboardingCompleted"))
        #expect(!defaults.bool(forKey: "setupIncomplete"))
        #expect(model.setupWarning == nil)
        #expect(installer.installedInto.map(\.path) == [folder.path])
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("AGENTS.md").path))
        #expect(try String(contentsOf: folder.appendingPathComponent("CLAUDE.md"), encoding: .utf8) == "@AGENTS.md\n")
    }

    @Test func finishWithoutStarterFilesWhenUnchecked() async throws {
        let (model, _, _, _) = makeModel()
        await settle(model)
        let folder = try makeTempDirectory()
        model.setFolder(folder.path)
        model.createStarterFiles = false
        model.syncNow = false
        _ = await model.finish()
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("AGENTS.md").path))
    }

    @Test func finishingWithMissingRequirementsRaisesAWarning() async throws {
        let (model, _, defaults, _) = makeModel(table: [:])
        await settle(model)
        model.setFolder(try makeTempDirectory().path)
        model.syncNow = false
        #expect(await model.finish())
        #expect(defaults.bool(forKey: "onboardingCompleted"))
        #expect(defaults.bool(forKey: "setupIncomplete"))
        #expect(model.setupWarning?.contains("Python 3") == true)
    }

    @Test func autoPresentsOnlyOnFirstRunAndOnlyOncePerLaunch() {
        let (model, _, defaults, _) = makeModel()
        #expect(model.consumeAutoPresent())
        #expect(!model.consumeAutoPresent())
        defaults.set(true, forKey: "onboardingCompleted")
        #expect(!model.consumeAutoPresent())
    }

    @Test func forceFlagPresentsEvenWhenCompleted() {
        let suite = "catedra-onboarding-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(true, forKey: "onboardingCompleted")
        defaults.set(true, forKey: "CatedraForceOnboarding")
        let model = OnboardingModel(settings: SettingsModel(store: EmptyCredentialStore(), defaults: defaults), auth: FakeAuth(),
                                    probe: FakeProbe(), commands: NoCommands(), installer: nil, defaults: defaults)
        #expect(model.consumeAutoPresent())
    }
}
