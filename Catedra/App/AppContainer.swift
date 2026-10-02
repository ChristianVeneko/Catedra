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

    init() {
        let credentials = KeychainCredentialStore()
        let reader = FileSystemWorkspace()
        let settings = SettingsModel(store: credentials)
        let workspace = WorkspaceModel(settings: settings, reader: reader)
        self.reader = reader
        self.settings = settings
        self.workspace = workspace
        self.sync = SyncModel(
            useCase: SyncUseCase(syncer: PythonSyncAdapter(), credentials: credentials, reader: reader),
            workspace: workspace)
        self.importFiles = ImportFilesUseCase(makeImporter: { FileSystemImporter(workspaceRoot: $0) })
    }
}
