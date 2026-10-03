import Foundation

/// `claude -p <prompt> --output-format stream-json --verbose --permission-mode <m> [--add-dir <d>]… [--model]
/// [--resume <id>]`. Attachments outside the working directory get their folder via `--add-dir` so the CLI can read them.
struct ClaudeProvider: AgentProvider {
    let id = AgentProviderID.claude
    let supportsResume = true

    static func permissionMode(for level: AgentPermissionLevel) -> String {
        switch level {
        case .readOnly: "plan"
        case .acceptEdits: "acceptEdits"
        case .automatic: "auto"
        case .unrestricted: "bypassPermissions"
        }
    }

    func buildArguments(prompt: String, options: AgentOptions, resume: String?, cwd: URL, knownCommands: Set<String>) -> [String] {
        var args = ["-p", prompt, "--output-format", "stream-json", "--verbose",
                    "--permission-mode", Self.permissionMode(for: id.normalized(options.permission))]
        for directory in ScopeRelativePath.extraDirectories(in: prompt, cwd: cwd) { args += ["--add-dir", directory] }
        if let model = options.model, !model.isEmpty { args += ["--model", model] }
        if let session = resume, !session.isEmpty { args += ["--resume", session] }
        return args
    }

    func makeParser() -> any AgentEventParsing { ClaudeStreamParser() }
}
