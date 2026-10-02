import Foundation

/// Incremental translator from a provider's raw stdout to normalized `AgentEvent`s. Implementations are pure,
/// tolerant (unknown events ignored, malformed lines skipped) and never throw.
protocol AgentEventParsing: Sendable {
    /// Feeds raw output bytes; returns events for every complete line.
    mutating func feed(_ data: Data) -> [AgentEvent]
    /// Flushes a trailing line without newline and any buffered text.
    mutating func finish() -> [AgentEvent]
    /// Called once after the process exited normally (not cancelled). Providers whose stream has no terminal event
    /// (OpenCode) synthesize the final result here.
    mutating func complete(exitStatus: Int32) -> [AgentEvent]
}

extension AgentEventParsing {
    mutating func complete(exitStatus: Int32) -> [AgentEvent] { [] }
}

/// Splits a byte stream into UTF-8 lines; partial lines (and split multi-byte characters) are retained.
struct JSONLineBuffer: Sendable {
    private var buffer = Data()

    mutating func feed(_ data: Data) -> [String] {
        buffer.append(data)
        var lines: [String] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            lines.append(String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self))
            buffer.removeSubrange(buffer.startIndex...newline)
        }
        return lines
    }

    mutating func flush() -> String? {
        defer { buffer = Data() }
        return buffer.isEmpty ? nil : String(decoding: buffer, as: UTF8.self)
    }

    /// Decodes one line into a JSON object, or nil when it is blank, malformed or not an object.
    static func object(from line: String) -> [String: Any]? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return (try? JSONSerialization.jsonObject(with: Data(trimmed.utf8))) as? [String: Any]
    }
}
