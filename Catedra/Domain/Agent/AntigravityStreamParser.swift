import Foundation

/// Pure, tolerant translator from Antigravity (`agy -p … --output-format stream-json`) NDJSON to `AgentEvent`s.
///
/// The stream is keyed by `event` (not `type`): `init`, `step_update` and `result`. Assistant text arrives as
/// `text_delta` chunks of one `step_index`; they are accumulated and emitted as a single block when the step finishes
/// (or when another step or the result begins). A `tool` step goes ACTIVE (→ tool use) then DONE (→ tool result);
/// any other terminal state is an error.
struct AntigravityStreamParser: AgentEventParsing {
    private var lines = JSONLineBuffer()
    private var textSteps: [Int: String] = [:]
    private var openTools: Set<Int> = []
    private var sessionId: String?

    mutating func feed(_ data: Data) -> [AgentEvent] {
        lines.feed(data).flatMap { parse(line: $0) }
    }

    mutating func finish() -> [AgentEvent] {
        let tail = lines.flush().map { parse(line: $0) } ?? []
        return tail + flushText()
    }

    mutating func parse(line: String) -> [AgentEvent] {
        guard let object = JSONLineBuffer.object(from: line), let event = object["event"] as? String else { return [] }
        switch event {
        case "init":
            guard let id = object["conversation_id"] as? String, !id.isEmpty else { return [] }
            sessionId = id
            return [.initialized(sessionId: id, model: nil)]
        case "step_update":
            guard let update = object["step_update"] as? [String: Any] else { return [] }
            return parseStep(update)
        case "result":
            guard let result = object["result"] as? [String: Any] else { return [] }
            return flushText() + [parseResult(result)]
        default:
            return []
        }
    }

    // MARK: - Steps

    private mutating func parseStep(_ update: [String: Any]) -> [AgentEvent] {
        guard let index = (update["step_index"] as? NSNumber)?.intValue,
              let type = update["step_type"] as? String else { return [] }
        let state = update["state"] as? String ?? ""
        switch type {
        case "agent_response":
            if let delta = update["text_delta"] as? String { textSteps[index, default: ""] += delta }
            return state == "ACTIVE" ? [] : flushText(step: index)
        case "tool":
            return parseTool(update, index: index, state: state)
        default:
            return [] // user_input and unknown step types
        }
    }

    private mutating func parseTool(_ update: [String: Any], index: Int, state: String) -> [AgentEvent] {
        let info = update["tool_info"] as? [String: Any] ?? [:]
        let name = update["tool_name"] as? String ?? info["name"] as? String ?? "tool"
        let id = "step-\(index)"
        var events = flushText()
        if openTools.insert(index).inserted {
            events.append(.toolUse(id: id, name: name,
                                   summary: ToolSummary.summarize(name: name, input: info["parameters"] as? [String: Any] ?? [:])))
        }
        guard state != "ACTIVE" else { return events }
        openTools.remove(index)
        let output = (info["output"] as? String) ?? (info["error"] as? String) ?? ""
        events.append(.toolResult(toolUseId: id, isError: state != "DONE", preview: ClaudeStreamParser.truncate(output)))
        return events
    }

    private mutating func flushText(step: Int? = nil) -> [AgentEvent] {
        let keys = step.map { [$0] } ?? textSteps.keys.sorted()
        var events: [AgentEvent] = []
        for key in keys {
            guard let text = textSteps.removeValue(forKey: key) else { continue }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { events.append(.assistantText(trimmed)) }
        }
        return events
    }

    // MARK: - Result

    private func parseResult(_ result: [String: Any]) -> AgentEvent {
        let status = result["status"] as? String ?? ""
        let usage = result["usage"] as? [String: Any]
        return .result(AgentResult(
            isError: status != "SUCCESS",
            subtype: status,
            text: result["response"] as? String ?? "",
            sessionId: result["conversation_id"] as? String ?? sessionId,
            costUSD: nil,
            durationMs: (result["duration_seconds"] as? NSNumber).map { Int(($0.doubleValue * 1000).rounded()) },
            inputTokens: (usage?["input_tokens"] as? NSNumber)?.intValue,
            outputTokens: (usage?["output_tokens"] as? NSNumber)?.intValue))
    }
}
