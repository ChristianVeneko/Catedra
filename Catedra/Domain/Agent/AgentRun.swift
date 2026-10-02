import Foundation

/// A conversation with an agent in one scope. Continuing it (`--resume`) appends turns to the same run.
struct AgentRun: Codable, Identifiable, Equatable, Sendable {
    enum Status: String, Codable, Sendable { case running, succeeded, failed, cancelled }

    let id: UUID
    let scope: AgentScopeRef
    var prompt: String
    var recipeID: String?
    var recipeTitle: String?
    var status: Status
    var sessionId: String?
    let startedAt: Date
    var turnStartedAt: Date
    var finishedAt: Date?
    var costUSD: Double
    var model: String?
    var transcript: [AgentEvent]

    init(id: UUID = UUID(), scope: AgentScopeRef, prompt: String, recipeID: String?, recipeTitle: String?, at date: Date) {
        self.id = id
        self.scope = scope
        self.prompt = prompt
        self.recipeID = recipeID
        self.recipeTitle = recipeTitle
        self.status = .running
        self.sessionId = nil
        self.startedAt = date
        self.turnStartedAt = date
        self.finishedAt = nil
        self.costUSD = 0
        self.model = nil
        self.transcript = [.userPrompt(prompt)]
    }

    var title: String {
        if let recipeTitle, !recipeTitle.isEmpty { return recipeTitle }
        return prompt.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? prompt
    }

    var isRunning: Bool { status == .running }

    /// Denials reported by the most recent turn.
    var latestDenials: [PermissionDenial] {
        var found: [PermissionDenial] = []
        for event in transcript.reversed() {
            if case .userPrompt = event { break }
            if case .denials(let d) = event { found = d; break }
        }
        return found
    }

    mutating func beginTurn(prompt: String, at date: Date) {
        status = .running
        finishedAt = nil
        turnStartedAt = date
        transcript.append(.userPrompt(prompt))
    }

    mutating func apply(_ event: AgentEvent, at date: Date) {
        switch event {
        case .initialized(let id, let model):
            sessionId = id
            if let model { self.model = model }
        case .result(let result):
            if let id = result.sessionId { sessionId = id }
            costUSD += result.costUSD ?? 0
            status = result.isError ? .failed : .succeeded
            finishedAt = date
            transcript.append(event)
        case .error:
            if status == .running { status = .failed; finishedAt = date }
            transcript.append(event)
        case .commandsCatalog:
            break // consumed by the command catalog, not part of the conversation
        default:
            transcript.append(event)
        }
    }

    mutating func finish(as newStatus: Status, at date: Date) {
        status = newStatus
        finishedAt = date
    }
}

/// UI-facing grouping of raw events: tool calls are paired with their results.
enum TranscriptItem: Identifiable, Equatable {
    struct ToolOutcome: Equatable { let isError: Bool; let preview: String }

    case user(id: Int, text: String)
    case assistant(id: Int, text: String)
    case thinking(id: Int, text: String)
    case tool(id: Int, name: String, summary: String, result: ToolOutcome?)
    case denials(id: Int, [PermissionDenial])
    case error(id: Int, text: String)

    var id: Int {
        switch self {
        case .user(let id, _), .assistant(let id, _), .thinking(let id, _), .tool(let id, _, _, _),
             .denials(let id, _), .error(let id, _): id
        }
    }

    static func build(from events: [AgentEvent]) -> [TranscriptItem] {
        var items: [TranscriptItem] = []
        var toolIndex: [String: Int] = [:]
        var assistantInTurn = false
        for (i, event) in events.enumerated() {
            switch event {
            case .initialized: break
            case .userPrompt(let text):
                assistantInTurn = false
                items.append(.user(id: i, text: text))
            case .assistantText(let text):
                assistantInTurn = true
                items.append(.assistant(id: i, text: text))
            case .thinking(let text):
                items.append(.thinking(id: i, text: text))
            case .toolUse(let id, let name, let summary):
                toolIndex[id] = items.count
                items.append(.tool(id: i, name: name, summary: summary, result: nil))
            case .toolResult(let toolUseId, let isError, let preview):
                if let idx = toolIndex[toolUseId], case .tool(let tid, let name, let summary, _) = items[idx] {
                    items[idx] = .tool(id: tid, name: name, summary: summary, result: ToolOutcome(isError: isError, preview: preview))
                }
            case .denials(let list):
                if !list.isEmpty { items.append(.denials(id: i, list)) }
            case .result(let result):
                if !assistantInTurn, !result.text.isEmpty { items.append(.assistant(id: i, text: result.text)) }
            case .error(let text):
                items.append(.error(id: i, text: text))
            case .commandsCatalog: break
            }
        }
        return items
    }
}
