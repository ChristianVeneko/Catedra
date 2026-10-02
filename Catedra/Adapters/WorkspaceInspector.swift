import Foundation

struct WorkspaceInspection: Sendable, Equatable {
    var exists: Bool
    var isWritable: Bool
    /// Number of activities in `_sistema/data/activities.json`; nil when the file is missing or unreadable.
    var existingActivityCount: Int?
    var hasAgentInstructions: Bool
    var isEmpty: Bool
}

/// Looks at a candidate workspace folder: writable? already synced? has agent instructions?
struct WorkspaceInspector: Sendable {
    func inspect(_ url: URL) -> WorkspaceInspection {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        let exists = fm.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
        let writable = exists ? fm.isWritableFile(atPath: url.path) : parentIsWritable(url)
        let contents = exists ? ((try? fm.contentsOfDirectory(atPath: url.path)) ?? []).filter { !$0.hasPrefix(".") } : []
        return WorkspaceInspection(
            exists: exists, isWritable: writable,
            existingActivityCount: activityCount(in: url),
            hasAgentInstructions: ["CLAUDE.md", "AGENTS.md"].contains { fm.fileExists(atPath: url.appendingPathComponent($0).path) },
            isEmpty: contents.isEmpty)
    }

    private func parentIsWritable(_ url: URL) -> Bool {
        var parent = url.deletingLastPathComponent()
        let fm = FileManager.default
        while !fm.fileExists(atPath: parent.path), parent.path != "/" { parent = parent.deletingLastPathComponent() }
        return fm.isWritableFile(atPath: parent.path)
    }

    private func activityCount(in root: URL) -> Int? {
        let file = root.appendingPathComponent(FileSystemWorkspace.activitiesRelativePath)
        guard let data = try? Data(contentsOf: file),
              let array = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else { return nil }
        return array.count
    }
}

/// Writes the starter `AGENTS.md` / `CLAUDE.md` into a new workspace; existing files are never touched.
struct StarterFilesWriter: Sendable {
    /// Names of the files that were created.
    func write(into folder: URL) throws -> [String] {
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        var created: [String] = []
        for (name, text) in [("AGENTS.md", StarterInstructions.agentsMarkdown), ("CLAUDE.md", StarterInstructions.claudeMarkdown)] {
            let target = folder.appendingPathComponent(name)
            guard !fm.fileExists(atPath: target.path) else { continue }
            try Data(text.utf8).write(to: target, options: .withoutOverwriting)
            created.append(name)
        }
        return created
    }
}
