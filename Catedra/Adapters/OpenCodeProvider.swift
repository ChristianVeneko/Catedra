import Foundation

/// `opencode run --format json --dir <cwd> [--agent plan | --auto] [-m provider/model] [-s <session>]
/// [--command <name>] -- <message>`.
///
/// OpenCode has no permission-mode flag: without `--auto` every permission request is auto-rejected, which is the
/// "accept edits" equivalent here; read-only selects the built-in `plan` agent.
struct OpenCodeProvider: AgentProvider {
    let id = AgentProviderID.opencode
    let supportsResume = true

    static func permissionArguments(for level: AgentPermissionLevel) -> [String] {
        switch level {
        case .readOnly: ["--agent", "plan"]
        case .acceptEdits, .automatic: []
        case .unrestricted: ["--auto"]
        }
    }

    /// `/name rest` → `("name", "rest")` when `name` is a known OpenCode command.
    static func commandInvocation(in prompt: String, known: Set<String>) -> (name: String, arguments: String)? {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return nil }
        let parts = trimmed.dropFirst().split(maxSplits: 1, whereSeparator: \.isWhitespace)
        guard let head = parts.first, known.contains(String(head)) else { return nil }
        return (String(head), parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : "")
    }

    func buildArguments(prompt: String, options: AgentOptions, resume: String?, cwd: URL, knownCommands: Set<String>) -> [String] {
        var args = ["run", "--format", "json", "--dir", cwd.path]
        args += Self.permissionArguments(for: id.normalized(options.permission))
        if let model = options.model, !model.isEmpty { args += ["-m", model] }
        if let session = resume, !session.isEmpty { args += ["--session", session] }
        var message = prompt
        if let invocation = Self.commandInvocation(in: prompt, known: knownCommands) {
            args += ["--command", invocation.name]
            message = invocation.arguments
        }
        if !message.isEmpty { args += ["--", message] }
        return args
    }

    func makeParser() -> any AgentEventParsing { OpenCodeEventParser() }
}

/// Lookup of the provider implementations.
enum AgentProviders {
    static func provider(for id: AgentProviderID) -> any AgentProvider {
        switch id {
        case .claude: ClaudeProvider()
        case .antigravity: AntigravityProvider()
        case .opencode: OpenCodeProvider()
        }
    }
}
