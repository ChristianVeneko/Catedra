import Foundation

/// Pure, tolerant translator from `opencode run --format json` lines to `AgentEvent`s.
///
/// Every line is `{type, timestamp, sessionID, …}` with `type` in `step_start`, `text`, `reasoning`, `tool_use`,
/// `step_finish` and `error` (confirmed in `packages/opencode/src/cli/cmd/run.ts`; part shapes in the SDK's
/// `types.gen.ts`). There is no terminal "result" event: success is "process exited 0 without an `error` event",
/// so `complete(exitStatus:)` synthesizes the result from the accumulated text, cost and tokens.
struct OpenCodeEventParser: AgentEventParsing {
    private var lines = JSONLineBuffer()
    private var sessionId: String?
    private var lastText = ""
    private var cost = 0.0
    private var sawCost = false
    private var inputTokens = 0
    private var outputTokens = 0
    private var firstTimestamp: Double?
    private var lastTimestamp: Double?
    private var denials: [PermissionDenial] = []
    private var sawError = false

    mutating func feed(_ data: Data) -> [AgentEvent] {
        lines.feed(data).flatMap { parse(line: $0) }
    }

    mutating func finish() -> [AgentEvent] {
        lines.flush().map { parse(line: $0) } ?? []
    }

    mutating func complete(exitStatus: Int32) -> [AgentEvent] {
        guard exitStatus == 0, !sawError, let sessionId else { return [] }
        var events: [AgentEvent] = []
        if !denials.isEmpty { events.append(.denials(denials)) }
        let duration: Int? = if let first = firstTimestamp, let last = lastTimestamp { Int(max(0, last - first)) } else { nil }
        events.append(.result(AgentResult(isError: false, subtype: "success", text: lastText, sessionId: sessionId,
                                          costUSD: sawCost ? cost : nil, durationMs: duration,
                                          inputTokens: inputTokens, outputTokens: outputTokens)))
        return events
    }

    mutating func parse(line: String) -> [AgentEvent] {
        guard let object = JSONLineBuffer.object(from: line), let type = object["type"] as? String else { return [] }
        var events: [AgentEvent] = []
        if let id = object["sessionID"] as? String, !id.isEmpty, sessionId == nil {
            sessionId = id
            events.append(.initialized(sessionId: id, model: nil))
        }
        if let stamp = (object["timestamp"] as? NSNumber)?.doubleValue {
            firstTimestamp = firstTimestamp ?? stamp
            lastTimestamp = stamp
        }
        let part = object["part"] as? [String: Any] ?? [:]
        switch type {
        case "text":
            let text = (part["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { lastText = text; events.append(.assistantText(text)) }
        case "reasoning":
            let text = (part["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { events.append(.thinking(text)) }
        case "tool_use":
            events += parseTool(part)
        case "step_finish":
            accumulate(part)
        case "error":
            sawError = true
            events.append(.error(Self.message(from: object["error"] as? [String: Any])))
        default:
            break
        }
        return events
    }

    // MARK: - Pieces

    private mutating func parseTool(_ part: [String: Any]) -> [AgentEvent] {
        guard let id = part["callID"] as? String, let name = part["tool"] as? String,
              let state = part["state"] as? [String: Any] else { return [] }
        let input = state["input"] as? [String: Any] ?? [:]
        let summary = ToolSummary.summarize(name: name, input: input)
        let failed = state["status"] as? String == "error"
        let output = failed ? (state["error"] as? String ?? "") : (state["output"] as? String ?? "")
        if failed, Self.isPermissionDenial(output) { denials.append(PermissionDenial(toolName: name, summary: summary)) }
        return [.toolUse(id: id, name: name, summary: summary),
                .toolResult(toolUseId: id, isError: failed, preview: ClaudeStreamParser.truncate(output))]
    }

    private mutating func accumulate(_ part: [String: Any]) {
        if let value = (part["cost"] as? NSNumber)?.doubleValue { cost += value; sawCost = true }
        if let tokens = part["tokens"] as? [String: Any] {
            inputTokens += (tokens["input"] as? NSNumber)?.intValue ?? 0
            outputTokens += (tokens["output"] as? NSNumber)?.intValue ?? 0
        }
    }

    private static func message(from error: [String: Any]?) -> String {
        if let data = error?["data"] as? [String: Any], let message = data["message"] as? String, !message.isEmpty { return message }
        return error?["name"] as? String ?? "OpenCode terminó con un error."
    }

    private static func isPermissionDenial(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("rejected permission") || lower.contains("prevents you from using")
    }
}
