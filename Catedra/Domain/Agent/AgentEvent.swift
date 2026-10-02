import Foundation

struct PermissionDenial: Codable, Hashable, Sendable {
    let toolName: String
    let summary: String
}

struct AgentResult: Codable, Hashable, Sendable {
    let isError: Bool
    let subtype: String
    let text: String
    let sessionId: String?
    let costUSD: Double?
    let durationMs: Int?
    var inputTokens: Int? = nil
    var outputTokens: Int? = nil
}

/// One normalized event of an agent conversation, produced by `AgentStreamParser` or by the app itself.
enum AgentEvent: Codable, Hashable, Sendable {
    case initialized(sessionId: String, model: String?)
    case userPrompt(String)
    case assistantText(String)
    case thinking(String)
    case toolUse(id: String, name: String, summary: String)
    case toolResult(toolUseId: String, isError: Bool, preview: String)
    case denials([PermissionDenial])
    case result(AgentResult)
    case error(String)
    /// Slash commands reported by the CLI. `complete` is false for the names-only `init` fallback. Never part of a transcript.
    case commandsCatalog([SlashCommand], complete: Bool)
}
