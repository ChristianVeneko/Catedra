import Foundation

/// Where one provider keeps its skills and custom commands.
struct CommandLayout: Sendable {
    /// Hidden folders searched in the working folder and every ancestor up to home (closest first).
    var projectFolders: [String]
    /// Extra user-level base folders, relative to home.
    var userFolders: [String]
    /// Subfolders of a base holding `<name>/SKILL.md`.
    var skillFolders: [String]
    /// Subfolders of a base holding `<name>.md` command files.
    var commandFolders: [String]
    /// Commands in subfolders get a path-like name (`group/name`), as OpenCode does.
    var nestedCommands: Bool

    static let claude = CommandLayout(projectFolders: [".claude"], userFolders: [".claude"], skillFolders: ["skills"],
                                      commandFolders: ["commands"], nestedCommands: false)
    /// Antigravity: skills in `.agents/skills` (also `.agent`, `_agents`, `_agent`), user skills in `~/.agents` or
    /// `~/.gemini/config`.
    static let antigravity = CommandLayout(projectFolders: [".agents", ".agent", "_agents", "_agent"],
                                           userFolders: [".agents", ".gemini/config"], skillFolders: ["skills"],
                                           commandFolders: [], nestedCommands: false)
    /// OpenCode: markdown commands in `.opencode/{command,commands}` and `~/.config/opencode/{command,commands}`.
    static let opencode = CommandLayout(projectFolders: [".opencode"], userFolders: [".config/opencode"], skillFolders: [],
                                        commandFolders: ["command", "commands"], nestedCommands: true)

    static func layout(for provider: AgentProviderID) -> CommandLayout {
        switch provider {
        case .claude: .claude
        case .antigravity: .antigravity
        case .opencode: .opencode
        }
    }
}

/// Offline source of a provider's commands: reads `SKILL.md` / command-file frontmatter from the user's folders and
/// from every project folder between the working folder and the home directory. Costs no tokens.
struct LocalSlashCommandScanner: SlashCommandScanning {
    var home: URL = FileManager.default.homeDirectoryForCurrentUser
    var layout: CommandLayout = .claude

    func scan(folder: URL) -> [SlashCommand] {
        var seen = Set<String>()
        var result: [SlashCommand] = []
        for base in baseFolders(for: folder) {
            var found: [SlashCommand] = []
            for sub in layout.skillFolders { found += skills(in: base.appendingPathComponent(sub)) }
            for sub in layout.commandFolders { found += commands(in: base.appendingPathComponent(sub)) }
            for command in found where seen.insert(command.name).inserted { result.append(command) }
        }
        return result.sorted { $0.name < $1.name }
    }

    /// Closest folder first, so project definitions win over user ones.
    private func baseFolders(for folder: URL) -> [URL] {
        let homePath = home.standardizedFileURL.path
        var folders: [URL] = []
        var current = folder.standardizedFileURL
        while true {
            for name in layout.projectFolders { folders.append(current.appendingPathComponent(name)) }
            if current.path == homePath || current.path == "/" { break }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { break }
            current = parent
        }
        for name in layout.userFolders {
            let url = home.appendingPathComponent(name)
            if !folders.contains(where: { $0.standardizedFileURL.path == url.standardizedFileURL.path }) { folders.append(url) }
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
        commandFiles(in: directory, prefix: "").compactMap { file, name in
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
            return command(from: text, fallbackName: name, explicitName: layout.nestedCommands)
        }
    }

    private func commandFiles(in directory: URL, prefix: String) -> [(URL, String)] {
        var files: [(URL, String)] = []
        for entry in contents(of: directory) {
            let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDirectory {
                if layout.nestedCommands { files += commandFiles(in: entry, prefix: prefix + entry.lastPathComponent + "/") }
            } else if entry.pathExtension == "md" {
                files.append((entry, prefix + entry.deletingPathExtension().lastPathComponent))
            }
        }
        return files
    }

    /// `explicitName` ignores a frontmatter `name`: OpenCode names commands after their path.
    private func command(from text: String, fallbackName: String, explicitName: Bool = false) -> SlashCommand {
        let meta = SkillFrontmatter.parse(text)
        return SlashCommand(name: explicitName ? fallbackName : (meta.name ?? fallbackName), description: meta.description ?? "",
                            argumentHint: meta.argumentHint, aliases: [], kind: .skill)
    }
}
