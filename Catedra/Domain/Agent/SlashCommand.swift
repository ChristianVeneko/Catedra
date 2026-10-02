import Foundation

/// A command offered by the composer popup: a Claude Code skill or builtin, or a command handled by the app itself.
struct SlashCommand: Codable, Hashable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable { case skill, builtin, app }

    let name: String
    let description: String
    let argumentHint: String?
    let aliases: [String]
    let kind: Kind

    var id: String { "\(kind.rawValue):\(name)" }
}

/// A command that survived matching, with the character offsets of `name` to highlight.
struct SlashCommandMatch: Hashable, Identifiable, Sendable {
    let command: SlashCommand
    let score: Int
    let highlight: [Int]

    var id: String { command.id }
}

struct SlashCommandSection: Identifiable, Equatable, Sendable {
    let kind: SlashCommand.Kind
    let title: String
    let matches: [SlashCommandMatch]

    var id: String { kind.rawValue }
}

/// Pure rules that combine the command sources into what the popup shows.
enum SlashCommandCatalogPolicy {
    /// Commands that only make sense in the interactive terminal UI and do nothing in `claude -p`.
    static let terminalOnly: Set<String> = [
        "doctor", "color", "focus", "reload-plugins", "login", "logout", "vim", "terminal-setup", "ide", "theme",
        "tui", "statusline", "exit", "quit", "help", "bug", "feedback", "upgrade", "mobile", "ios", "android",
        "desktop", "app", "keybindings", "voice", "stickers", "release-notes", "privacy-settings", "hooks",
    ]

    /// Builtins that `init.slash_commands` (names only) cannot tell apart from skills.
    static let knownBuiltins: Set<String> = [
        "compact", "clear", "model", "config", "cost", "context", "init", "review", "memory", "mcp", "agents",
        "permissions", "add-dir", "status", "usage", "export", "rewind", "security-review", "pr-comments",
    ]

    static func title(for kind: SlashCommand.Kind) -> String {
        switch kind {
        case .app: "Cátedra"
        case .skill: "Skills"
        case .builtin: "Comandos de Claude Code"
        }
    }

    /// App commands win over same-named (or aliased) CLI commands; terminal-only commands are dropped;
    /// local scan results fill in names the CLI catalog does not know.
    static func merge(app: [SlashCommand], cli: [SlashCommand], local: [SlashCommand]) -> [SlashCommand] {
        let overridden = Set(app.flatMap { [$0.name] + $0.aliases }.map { $0.lowercased() })
        var seen = overridden
        var result = app
        for command in cli + local {
            let key = command.name.lowercased()
            guard !seen.contains(key), !terminalOnly.contains(key) else { continue }
            seen.insert(key)
            result.append(command)
        }
        return result
    }

    /// Groups ranked matches into popup sections (Cátedra, Skills, Claude Code), preserving rank inside each.
    static func sections(from matches: [SlashCommandMatch]) -> [SlashCommandSection] {
        [SlashCommand.Kind.app, .skill, .builtin].compactMap { kind in
            let group = matches.filter { $0.command.kind == kind }
            return group.isEmpty ? nil : SlashCommandSection(kind: kind, title: title(for: kind), matches: group)
        }
    }
}
