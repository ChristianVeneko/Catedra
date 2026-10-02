import Foundation
import Observation

/// Lazily built, cached index of the files under every course's `contenidos/`; rebuilt in the background when the
/// workspace changes.
@Observable @MainActor
final class ContentIndexModel {
    private(set) var entries: [ContentIndexEntry] = []
    /// Incremented whenever `entries` is replaced.
    private(set) var revision = 0
    private(set) var isBuilding = false

    private let workspace: WorkspaceModel
    @ObservationIgnored private var builtForRevision: Int?
    @ObservationIgnored private var hasBeenRequested = false

    init(workspace: WorkspaceModel) { self.workspace = workspace }

    /// Builds the index on first use, then whenever the workspace revision moved on.
    func refreshIfNeeded() {
        hasBeenRequested = true
        guard !isBuilding, builtForRevision != workspace.revision else { return }
        isBuilding = true
        let target = workspace.revision
        let reader = workspace.reader, root = workspace.root, courses = workspace.snapshot.courses
        Task {
            let built = await Task.detached(priority: .utility) {
                ContentIndexBuilder.entries(root: root, courses: courses, reader: reader)
            }.value
            entries = built
            revision += 1
            builtForRevision = target
            isBuilding = false
            if target != workspace.revision { refreshIfNeeded() }
        }
    }

    /// Workspace reloaded: refresh only if somebody already needed the index.
    func workspaceChanged() {
        if hasBeenRequested { refreshIfNeeded() }
    }
}
