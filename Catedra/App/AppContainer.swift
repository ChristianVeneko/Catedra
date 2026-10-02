import Foundation
import Observation

/// Composition root: wires adapters into use cases and view models.
@Observable @MainActor
final class AppContainer {
    let settings: SettingsModel
    let workspace: WorkspaceModel
    let navigation = NavigationModel()
    let sync: SyncModel
    let reader: WorkspaceReading
    let importFiles: ImportFilesUseCase
    let agents: AgentRunRegistry
    let commands: SlashCommandCatalog

    init() {
        // Under tests (or with CATEDRA_SKIP_KEYCHAIN=1) never touch the Keychain: a fresh ad-hoc signature would trigger
        // a blocking access prompt.
        let env = ProcessInfo.processInfo.environment
        let skipKeychain = env["XCTestConfigurationFilePath"] != nil || env["CATEDRA_SKIP_KEYCHAIN"] == "1"
        let credentials: CredentialStoring = skipKeychain ? EmptyCredentialStore() : KeychainCredentialStore()
        let reader = FileSystemWorkspace()
        let settings = SettingsModel(store: credentials)
        let workspace = WorkspaceModel(settings: settings, reader: reader)
        self.reader = reader
        self.settings = settings
        self.workspace = workspace
        self.sync = SyncModel(
            useCase: SyncUseCase(syncer: PythonSyncAdapter(), credentials: credentials, reader: reader),
            workspace: workspace)
        self.agents = AgentRunRegistry(runner: CLIAgentRunner(), store: JSONAgentRunStore(),
                                       notifier: UserNotificationAdapter(), terminal: TerminalLauncher(), settings: settings)
        let commands = SlashCommandCatalog(
            store: JSONSlashCommandCatalogStore(),
            scanners: Dictionary(uniqueKeysWithValues: AgentProviderID.allCases.map {
                ($0, LocalSlashCommandScanner(layout: .layout(for: $0)) as SlashCommandScanning)
            }))
        self.commands = commands
        self.agents.onCommandsCatalog = { [weak commands] list, complete, provider in
            commands?.ingest(list, complete: complete, provider: provider)
        }
        self.agents.knownCommands = { [weak commands] provider, folder in
            commands?.providerCommandNames(in: folder, provider: provider) ?? []
        }
        self.importFiles = ImportFilesUseCase(makeImporter: { FileSystemImporter(workspaceRoot: $0) })
    }
}

/// Credential store used when the Keychain must not be touched; holds nothing.
struct EmptyCredentialStore: CredentialStoring {
    func load() -> SAIACredentials? { nil }
    func save(_ credentials: SAIACredentials) throws {}
    func delete() throws {}
}
