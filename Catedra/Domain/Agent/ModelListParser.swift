import Foundation

/// Parsers for the output of `agy models` and `opencode models`, and for `--version`.
enum ModelListParser {
    /// `agy models`: a "Fetching available models..." line, then `<id>\t<display name>` lines.
    static func antigravity(_ output: String) -> [AgentModelOption] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, !parts[0].isEmpty, !parts[0].contains(" ") else { return nil }
            return AgentModelOption(id: parts[0], label: parts[1].isEmpty ? parts[0] : parts[1])
        }
    }

    /// `opencode models`: one `provider/model` per line.
    static func opencode(_ output: String) -> [AgentModelOption] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let id = line.trimmingCharacters(in: .whitespaces)
            guard id.contains("/"), !id.contains(" ") else { return nil }
            return AgentModelOption(id: id, label: id)
        }
    }

    static func parse(_ output: String, for provider: AgentProviderID) -> [AgentModelOption] {
        switch provider {
        case .claude: []
        case .antigravity: antigravity(output)
        case .opencode: opencode(output)
        }
    }
}

enum VersionParser {
    /// First dotted version number in `--version` output ("2.1.288 (Claude Code)", "v1.2.15").
    static func parse(_ output: String) -> String? {
        guard let range = output.range(of: #"\d+\.\d+(\.\d+)*"#, options: .regularExpression) else { return nil }
        return String(output[range])
    }
}
