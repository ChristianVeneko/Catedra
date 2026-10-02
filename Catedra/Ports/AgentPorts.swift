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
    /// Opens Terminal.app in `folder` running `command` (executable path first).
    func open(in folder: URL, command: [String]) throws
}

protocol SlashCommandCatalogStoring: Sendable {
    /// Last catalog reported by the CLI; empty when nothing is cached or the file is unreadable.
    func load() -> [SlashCommand]
    func save(_ commands: [SlashCommand]) throws
}

protocol SlashCommandScanning: Sendable {
    /// Skills and custom commands found on disk for a working folder (user level plus its ancestors).
    func scan(folder: URL) -> [SlashCommand]
}

/// Everything provider-specific about one agent CLI: how to call it, how to read its output, how to resume it.
protocol AgentProvider: Sendable {
    var id: AgentProviderID { get }
    /// True when a stored session id can continue the conversation.
    var supportsResume: Bool { get }
    /// Arguments for one headless turn (after the executable).
    func buildArguments(prompt: String, options: AgentOptions, resume: String?, cwd: URL, knownCommands: Set<String>) -> [String]
    func makeParser() -> any AgentEventParsing
    /// Extra environment variables for the child process.
    var environmentOverrides: [String: String] { get }
}

extension AgentProvider {
    var slashCatalogSource: AgentProviderID.SlashCatalogSource { id.slashCatalogSource }
    var environmentOverrides: [String: String] { [:] }

    /// Arguments of the interactive CLI that continue `sessionId` (empty when there is none).
    func terminalResumeCommand(sessionId: String?) -> [String] { id.terminalResumeArguments(sessionId: sessionId) }

    func locate(override: String?, locator: BinaryLocator? = nil) -> String? {
        (locator ?? BinaryLocator(provider: id)).locate(override: override)
    }
}
