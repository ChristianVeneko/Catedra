import Foundation
import Observation

/// Keeps the full-text index in sync with the workspace (off the main actor) and answers searches.
@Observable @MainActor
final class SearchIndexModel {
    static let resultLimit = 40

    private(set) var isIndexing = false
    /// Incremented after every indexing pass.
    private(set) var revision = 0
    private(set) var lastError: String?

    private let workspace: WorkspaceModel
    private let store: SearchIndexStoring?
    private let useCase: ContentIndexingUseCase?
    @ObservationIgnored private var needsAnotherPass = false

    /// `store` nil disables indexing and search (tests, unwritable Application Support).
    init(workspace: WorkspaceModel, store: SearchIndexStoring?,
         scanner: ContentFileScanning = FileSystemContentScanner(), extractor: ContentTextExtracting = FileContentTextExtractor()) {
        self.workspace = workspace
        self.store = store
        self.useCase = store.map { ContentIndexingUseCase(store: $0, scanner: scanner, extractor: extractor) }
    }

    /// Workspace (re)loaded: launch, sync completion, file watcher. Passes are coalesced.
    func workspaceChanged() {
        guard useCase != nil else { return }
        if isIndexing { needsAnotherPass = true; return }
        isIndexing = true
        Task { await runPasses() }
    }

    private func runPasses() async {
        guard let useCase else { return }
        repeat {
            needsAnotherPass = false
            let root = workspace.root, courses = workspace.snapshot.courses
            let failure = await Task.detached(priority: .utility) { () -> String? in
                do { try await useCase.run(root: root, courses: courses); return nil } catch { return error.localizedDescription }
            }.value
            lastError = failure
            revision += 1
        } while needsAnotherPass
        isIndexing = false
    }

    func search(_ query: String) async -> [ContentSearchHit] {
        guard let store, let match = SearchQuerySanitizer.matchExpression(from: query) else { return [] }
        let root = workspace.root
        let raw = (try? await store.search(match: match, limit: Self.resultLimit)) ?? []
        return raw.map { ContentSearchHit(raw: $0, root: root) }
    }
}
