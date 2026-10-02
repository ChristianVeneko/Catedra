import Foundation

/// Pure, tolerant translator from Claude Code `stream-json` lines to `AgentEvent`s.
/// Unknown event types and fields are ignored and malformed lines are skipped; it never throws.
struct AgentStreamParser: Sendable {
    static let previewLimit = 600

    private var buffer = Data()

    /// Feeds raw output bytes; returns events for every complete line. Partial lines (and split UTF-8) are retained.
    mutating func feed(_ data: Data) -> [AgentEvent] {
        buffer.append(data)
        var events: [AgentEvent] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            events += Self.parse(line: String(decoding: lineData, as: UTF8.self))
        }
        return events
    }

    /// Flushes a trailing line that had no newline.
    mutating func finish() -> [AgentEvent] {
        defer { buffer = Data() }
        guard !buffer.isEmpty else { return [] }
        return Self.parse(line: String(decoding: buffer, as: UTF8.self))
    }

    static func parse(line: String) -> [AgentEvent] {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let object = (try? JSONSerialization.jsonObject(with: Data(trimmed.utf8))) as? [String: Any],
              let type = object["type"] as? String else { return [] }
        switch type {
        case "system": return parseSystem(object)
        case "assistant": return parseAssistant(object)
        case "user": return parseUser(object)
        case "result": return parseResult(object)
        default: return []
        }
    }

    // MARK: - Per type

    private static func parseSystem(_ object: [String: Any]) -> [AgentEvent] {
        guard object["subtype"] as? String == "init", let id = object["session_id"] as? String else { return [] }
        return [.initialized(sessionId: id, model: object["model"] as? String)]
    }

    private static func contentBlocks(_ object: [String: Any]) -> [[String: Any]] {
        guard let message = object["message"] as? [String: Any],
              let content = message["content"] as? [[String: Any]] else { return [] }
        return content
    }

    private static func parseAssistant(_ object: [String: Any]) -> [AgentEvent] {
        contentBlocks(object).compactMap { block in
            switch block["type"] as? String {
            case "text":
                guard let text = block["text"] as? String, !text.isEmpty else { return nil }
                return .assistantText(text)
            case "thinking":
                guard let text = block["thinking"] as? String, !text.isEmpty else { return nil }
                return .thinking(text)
            case "tool_use":
                guard let id = block["id"] as? String, let name = block["name"] as? String else { return nil }
                return .toolUse(id: id, name: name, summary: ToolSummary.summarize(name: name, input: block["input"] as? [String: Any] ?? [:]))
            default:
                return nil
            }
        }
    }

    private static func parseUser(_ object: [String: Any]) -> [AgentEvent] {
        contentBlocks(object).compactMap { block in
            guard block["type"] as? String == "tool_result", let id = block["tool_use_id"] as? String else { return nil }
            return .toolResult(toolUseId: id, isError: block["is_error"] as? Bool ?? false, preview: preview(of: block["content"]))
        }
    }

    private static func parseResult(_ object: [String: Any]) -> [AgentEvent] {
        var events: [AgentEvent] = []
        if let raw = object["permission_denials"] as? [[String: Any]], !raw.isEmpty {
            events.append(.denials(raw.map {
                let name = $0["tool_name"] as? String ?? "?"
                return PermissionDenial(toolName: name, summary: ToolSummary.summarize(name: name, input: $0["tool_input"] as? [String: Any] ?? [:]))
            }))
        }
        let subtype = object["subtype"] as? String ?? ""
        events.append(.result(AgentResult(
            isError: object["is_error"] as? Bool ?? !(subtype == "success"),
            subtype: subtype,
            text: object["result"] as? String ?? "",
            sessionId: object["session_id"] as? String,
            costUSD: (object["total_cost_usd"] as? NSNumber)?.doubleValue,
            durationMs: (object["duration_ms"] as? NSNumber)?.intValue)))
        return events
    }

    private static func preview(of content: Any?) -> String {
        let text: String
        switch content {
        case let string as String: text = string
        case let blocks as [[String: Any]]:
            text = blocks.compactMap { $0["text"] as? String }.joined(separator: "\n")
        default: text = ""
        }
        return truncate(text)
    }

    static func truncate(_ text: String, limit: Int = previewLimit) -> String {
        text.count > limit ? String(text.prefix(limit)) + "…" : text
    }
}

/// One-line, human-oriented description of a tool call's input.
enum ToolSummary {
    private static let preferredKeys = ["file_path", "path", "command", "pattern", "skill", "url", "query", "description", "prompt"]

    static func summarize(name: String, input: [String: Any]) -> String {
        for key in preferredKeys {
            if let value = input[key] as? String, !value.isEmpty { return oneLine(value) }
        }
        if let value = input.keys.sorted().compactMap({ input[$0] as? String }).first(where: { !$0.isEmpty }) {
            return oneLine(value)
        }
        return ""
    }

    private static func oneLine(_ text: String) -> String {
        let first = text.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? text
        return first.count > 160 ? String(first.prefix(160)) + "…" : first
    }
}
