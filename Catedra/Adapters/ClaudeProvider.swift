import Foundation

/// Builds the argument list for a headless `claude` turn.
enum ClaudeCommand {
    static func arguments(for request: AgentRequest) -> [String] {
        var args = ["-p", request.prompt,
                    "--output-format", "stream-json", "--verbose",
                    "--permission-mode", request.options.permissionMode.rawValue]
        if let alias = request.options.model.cliAlias { args += ["--model", alias] }
        if let session = request.resumeSessionId, !session.isEmpty { args += ["--resume", session] }
        return args
    }
}
