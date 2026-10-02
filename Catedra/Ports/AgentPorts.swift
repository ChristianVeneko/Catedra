import Foundation

enum AgentRunnerError: Error, Equatable {
    case cancelled
}

protocol AgentRunning: Sendable {
    /// Launches one headless turn and streams normalized events. The stream finishes after the process exits;
    /// it throws `AgentRunnerError.cancelled` when `cancel(runID:)` stopped it.
    func start(_ request: AgentRequest) -> AsyncThrowingStream<AgentEvent, Error>
    func cancel(runID: UUID)
}

protocol AgentRunStoring: Sendable {
    func save(_ run: AgentRun) throws
    func loadAll() -> [AgentRun]
    func delete(id: UUID)
}

protocol AgentNotifying: Sendable {
    /// Asks for notification permission the first time it is called.
    func requestAuthorizationIfNeeded() async
    /// Posts a notification only when the app is not frontmost.
    func notifyFinished(title: String, body: String) async
}

protocol TerminalOpening: Sendable {
    func openClaude(in folder: URL, executablePath: String, sessionId: String?) throws
}
