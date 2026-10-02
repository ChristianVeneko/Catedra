import Foundation
import Observation

/// Tracks every agent conversation (running and historical), one per scope may run at a time.
@Observable @MainActor
final class AgentRunRegistry {
    private(set) var runs: [AgentRun] = []
    /// Selected conversation per scope id (nil entry = "new conversation").
    var selection: [String: UUID] = [:]
    private(set) var startErrors: [String: String] = [:]

    private let useCase: RunAgentUseCase
    private let store: AgentRunStoring
    private let notifier: AgentNotifying
    private let terminal: TerminalOpening
    private let settings: SettingsModel
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var authorizationRequested = false

    init(runner: AgentRunning, store: AgentRunStoring, notifier: AgentNotifying, terminal: TerminalOpening, settings: SettingsModel) {
        self.useCase = RunAgentUseCase(runner: runner, store: store)
        self.store = store
        self.notifier = notifier
        self.terminal = terminal
        self.settings = settings
    }

    // MARK: - Queries

    func runs(in scopeID: String) -> [AgentRun] { runs.filter { $0.scope.id == scopeID } }
    func run(id: UUID?) -> AgentRun? { id.flatMap { id in runs.first { $0.id == id } } }
    func selectedRun(in scopeID: String) -> AgentRun? { run(id: selection[scopeID]) }

    var runningRuns: [AgentRun] { runs.filter(\.isRunning) }
    var runningCount: Int { runningRuns.count }

    func isRunning(scopeID: String) -> Bool { runs.contains { $0.scope.id == scopeID && $0.isRunning } }

    /// True when the course itself or any of its activities has a running agent.
    func isRunning(inCourse folderName: String) -> Bool {
        runs.contains { $0.isRunning && $0.scope.courseFolderName == folderName }
    }

    // MARK: - Lifecycle

    /// Loads history; conversations left "running" by a previous launch are marked cancelled.
    func load() async {
        let store = self.store
        var loaded = await Task.detached { store.loadAll() }.value
        for i in loaded.indices where loaded[i].status == .running {
            loaded[i].finish(as: .cancelled, at: loaded[i].turnStartedAt)
            try? store.save(loaded[i])
        }
        let live = runs.filter(\.isRunning)
        runs = live + loaded.filter { l in !live.contains { $0.id == l.id } }
    }

    /// Starts a new conversation, or continues `continuing` (via `--resume`). Ignored while the scope is busy.
    func start(scope: AgentScope, prompt: String, recipe: Recipe?, options: AgentOptions, continuing runID: UUID? = nil) {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isRunning(scopeID: scope.id) else { return }
        startErrors[scope.id] = nil
        guard let executable = settings.resolvedClaudePath() else {
            startErrors[scope.id] = "No se encontró Claude Code. Indique su ruta en Ajustes › Agentes."
            return
        }
        let cwd = scope.url(in: settings.workspaceURL)
        guard FileManager.default.fileExists(atPath: cwd.path) else {
            startErrors[scope.id] = "La carpeta «\(scope.folder)» no existe en el espacio de trabajo."
            return
        }

        var run: AgentRun
        var resume: String?
        if let runID, var existing = self.run(id: runID) {
            existing.beginTurn(prompt: text, at: .now)
            resume = existing.sessionId
            run = existing
            replace(run)
        } else {
            run = AgentRun(scope: scope.ref, prompt: text, recipeID: recipe?.id, recipeTitle: recipe?.title, at: .now)
            runs.insert(run, at: 0)
        }
        selection[scope.id] = run.id

        let request = AgentRequest(runID: run.id, executablePath: executable, cwd: cwd, prompt: text,
                                   resumeSessionId: resume, options: options)
        let useCase = self.useCase
        let initial = run
        tasks[run.id] = Task { [weak self] in
            let registry = self
            await registry?.requestAuthorizationOnce()
            let final = await useCase.execute(run: initial, request: request) { updated in
                await registry?.replace(updated)
            }
            await registry?.finished(final)
        }
    }

    func stop(runID: UUID) {
        useCase.cancel(runID: runID)
    }

    func delete(runID: UUID) {
        guard let run = run(id: runID), !run.isRunning else { return }
        store.delete(id: runID)
        runs.removeAll { $0.id == runID }
        if selection[run.scope.id] == runID { selection[run.scope.id] = nil }
    }

    func openInTerminal(scope: AgentScope, run: AgentRun?) {
        guard let executable = settings.resolvedClaudePath() else {
            startErrors[scope.id] = "No se encontró Claude Code. Indique su ruta en Ajustes › Agentes."
            return
        }
        do {
            try terminal.openClaude(in: scope.url(in: settings.workspaceURL), executablePath: executable, sessionId: run?.sessionId)
        } catch {
            startErrors[scope.id] = "No se pudo abrir Terminal: \(error.localizedDescription)"
        }
    }

    // MARK: - Internals

    private func replace(_ run: AgentRun) {
        if let i = runs.firstIndex(where: { $0.id == run.id }) { runs[i] = run } else { runs.insert(run, at: 0) }
    }

    private func requestAuthorizationOnce() async {
        guard !authorizationRequested else { return }
        authorizationRequested = true
        await notifier.requestAuthorizationIfNeeded()
    }

    private func finished(_ run: AgentRun) async {
        replace(run)
        tasks[run.id] = nil
        guard run.status != .cancelled else { return }
        let body = run.status == .succeeded ? "Terminó correctamente." : "Terminó con errores."
        await notifier.notifyFinished(title: "Agente terminó: \(run.scope.title)", body: body)
    }
}
