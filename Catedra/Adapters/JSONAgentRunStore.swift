import Foundation

/// Stores one JSON file per run under `~/Library/Application Support/Catedra/agent-runs/` (never in the workspace),
/// keeping at most `maxRunsPerScope` runs per scope.
struct JSONAgentRunStore: AgentRunStoring {
    static let defaultMaxRunsPerScope = 30

    let directory: URL
    let maxRunsPerScope: Int

    init(directory: URL = JSONAgentRunStore.defaultDirectory, maxRunsPerScope: Int = JSONAgentRunStore.defaultMaxRunsPerScope) {
        self.directory = directory
        self.maxRunsPerScope = maxRunsPerScope
    }

    static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Catedra/agent-runs", isDirectory: true)
    }

    func save(_ run: AgentRun) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(run).write(to: file(for: run.id), options: .atomic)
        prune(scopeID: run.scope.id)
    }

    func loadAll() -> [AgentRun] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return files.filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(AgentRun.self, from: Data(contentsOf: $0)) }
            .sorted { $0.startedAt > $1.startedAt }
    }

    func delete(id: UUID) {
        try? FileManager.default.removeItem(at: file(for: id))
    }

    // MARK: - Helpers

    private func file(for id: UUID) -> URL { directory.appendingPathComponent("\(id.uuidString).json") }

    private func prune(scopeID: String) {
        let sameScope = loadAll().filter { $0.scope.id == scopeID }
        guard sameScope.count > maxRunsPerScope else { return }
        for old in sameScope.dropFirst(maxRunsPerScope) { delete(id: old.id) }
    }
}
