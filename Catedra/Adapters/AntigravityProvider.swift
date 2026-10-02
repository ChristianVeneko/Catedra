import Foundation

/// `agy -p <prompt> --output-format stream-json [--mode plan|accept-edits | --dangerously-skip-permissions]
/// [--model <id>] [--conversation <id>]`. Print mode runs with stdin closed.
struct AntigravityProvider: AgentProvider {
    let id = AgentProviderID.antigravity
    let supportsResume = true

    /// Flags for a permission level. Antigravity has no separate "auto" level; it falls back to accept-edits.
    static func permissionArguments(for level: AgentPermissionLevel) -> [String] {
        switch level {
        case .readOnly: ["--mode", "plan"]
        case .acceptEdits, .automatic: ["--mode", "accept-edits"]
        case .unrestricted: ["--dangerously-skip-permissions"]
        }
    }

    func buildArguments(prompt: String, options: AgentOptions, resume: String?, cwd: URL, knownCommands: Set<String>) -> [String] {
        var args = ["-p", prompt, "--output-format", "stream-json"]
        args += Self.permissionArguments(for: id.normalized(options.permission))
        if let model = options.model, !model.isEmpty { args += ["--model", model] }
        if let session = resume, !session.isEmpty { args += ["--conversation", session] }
        return args
    }

    func makeParser() -> any AgentEventParsing { AntigravityStreamParser() }
}
