import Foundation

/// `claude -p <prompt> --output-format stream-json --verbose --permission-mode <m> [--model] [--resume <id>]`.
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
        if let model = options.model, !model.isEmpty { args += ["--model", model] }
        if let session = resume, !session.isEmpty { args += ["--resume", session] }
        return args
    }

    func makeParser() -> any AgentEventParsing { ClaudeStreamParser() }
}
