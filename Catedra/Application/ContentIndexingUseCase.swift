import Foundation

/// Incremental indexing: scans the workspace, diffs it against the stored stamps and re-extracts only what changed.
struct ContentIndexingUseCase: Sendable {
    let store: SearchIndexStoring
    let scanner: ContentFileScanning
    let extractor: ContentTextExtracting

    @discardableResult
    func run(root: URL, courses: [Course]) async throws -> IndexingReport {
        try await store.ensureRoot(root.standardizedFileURL.path)
        let current = scanner.scan(root: root, courses: courses)
        let diff = IndexDiff.compute(stored: try await store.stamps(), current: current)
        if !diff.removed.isEmpty { try await store.remove(paths: diff.removed) }
        for path in diff.toIndex {
            try Task.checkCancellation()
            guard let stamp = current[path], let kind = SearchIndexPolicy.kind(forRelativePath: path) else { continue }
            let pages = extractor.pages(at: root.appendingPathComponent(path), kind: kind)
            try await store.replace(path: path, stamp: stamp, pages: pages)
        }
        return IndexingReport(added: diff.added.count, changed: diff.changed.count, removed: diff.removed.count)
    }
}
