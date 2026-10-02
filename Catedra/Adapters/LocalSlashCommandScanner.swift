import Foundation

/// Offline fallback for the command catalog: reads `skills/*/SKILL.md` and `commands/*.md` frontmatter from
/// `~/.claude` and from every `.claude` folder between the working folder and the home directory.
struct LocalSlashCommandScanner: SlashCommandScanning {
    var home: URL = FileManager.default.homeDirectoryForCurrentUser

    func scan(folder: URL) -> [SlashCommand] {
        var seen = Set<String>()
        var result: [SlashCommand] = []
        for base in claudeFolders(for: folder) {
            for command in skills(in: base.appendingPathComponent("skills")) + commands(in: base.appendingPathComponent("commands")) {
                if seen.insert(command.name).inserted { result.append(command) }
            }
        }
        return result.sorted { $0.name < $1.name }
    }

    /// Closest folder first, so project definitions win over user ones.
    private func claudeFolders(for folder: URL) -> [URL] {
        let homePath = home.standardizedFileURL.path
        var folders: [URL] = []
        var current = folder.standardizedFileURL
        while true {
            folders.append(current.appendingPathComponent(".claude"))
            if current.path == homePath || current.path == "/" { break }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { break }
            current = parent
        }
        if !folders.contains(where: { $0.deletingLastPathComponent().path == homePath }) {
            folders.append(home.appendingPathComponent(".claude"))
        }
        return folders
    }

    private func contents(of url: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
    }

    private func skills(in directory: URL) -> [SlashCommand] {
        contents(of: directory).compactMap { entry in
            let file = entry.appendingPathComponent("SKILL.md")
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
            return command(from: text, fallbackName: entry.lastPathComponent)
        }
    }

    private func commands(in directory: URL) -> [SlashCommand] {
        contents(of: directory).filter { $0.pathExtension == "md" }.compactMap { file in
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
            return command(from: text, fallbackName: file.deletingPathExtension().lastPathComponent)
        }
    }

    private func command(from text: String, fallbackName: String) -> SlashCommand {
        let meta = SkillFrontmatter.parse(text)
        return SlashCommand(name: meta.name ?? fallbackName, description: meta.description ?? "",
                            argumentHint: meta.argumentHint, aliases: [], kind: .skill)
    }
}
