import Foundation
import Observation

/// Run store that keeps nothing: weekly summary runs are not part of any conversation history.
struct DiscardingRunStore: AgentRunStoring {
    func save(_ run: AgentRun) throws {}
    func loadAll() -> [AgentRun] { [] }
    func delete(id: UUID) {}
}

/// Builds the weekly digest and, when the user enabled it, asks an agent to write the summary.
@Observable @MainActor
final class WeeklySummaryModel {
    private(set) var state = WeeklySummaryState()
    private(set) var markdown: String?
    private(set) var isGenerating = false
    private(set) var message: String?

    private let store: any StateStoring<WeeklySummaryState>
    private let useCase: RunAgentUseCase
    private let directory: URL
    private let notifier: AgentNotifying?
    /// Wired by the composition root.
    var isEnabled: @MainActor () -> Bool = { false }
    var digest: @MainActor (Date) -> WeeklyDigest = { WeeklyDigestBuilder.build(now: $0, activities: [], isOpen: { _ in true }, grades: [], studyBlocks: [], cardsDue: 0) }
    /// Provider, executable and options of the chosen agent; nil when none is available.
    var agent: @MainActor () -> (provider: AgentProviderID, executable: String, options: AgentOptions)? = { nil }
    @ObservationIgnored private var task: Task<Void, Never>?

    init(store: any StateStoring<WeeklySummaryState>, runner: AgentRunning, directory: URL, notifier: AgentNotifying? = nil) {
        self.store = store
        self.useCase = RunAgentUseCase(runner: runner, store: DiscardingRunStore())
        self.directory = directory
        self.notifier = notifier
    }

    static var defaultDirectory: URL { JSONStateStore<WeeklySummaryState>.supportFile("weekly-summaries") }

    func load() {
        state = store.load() ?? WeeklySummaryState()
        if let latest = state.latest { markdown = try? String(contentsOf: file(for: latest.weekKey), encoding: .utf8) }
    }

    /// The summary of the current week, unless the user dismissed it.
    func card(now: Date = .now) -> (text: String, usedAgent: Bool)? {
        let key = WeeklySchedule.weekKey(for: now)
        guard let latest = state.latest, latest.weekKey == key, state.dismissedWeekKey != key, let markdown else { return nil }
        return (markdown, latest.usedAgent)
    }

    func dismiss(now: Date = .now) {
        state.dismissedWeekKey = WeeklySchedule.weekKey(for: now)
        persist()
    }

    /// Generates the summary when this is the first launch or wake on or after Monday 07:00 of the week.
    func checkIfDue(now: Date = .now) {
        guard !isGenerating, WeeklySchedule.isDue(now: now, lastWeekKey: state.lastWeekKey, enabled: isEnabled()) else { return }
        generate(now: now)
    }

    /// Manual "Generar resumen ahora"; also what the scheduled path runs.
    func generate(now: Date = .now) {
        guard !isGenerating else { return }
        isGenerating = true
        message = nil
        let digest = digest(now)
        let key = digest.weekKey
        state.lastWeekKey = key
        persist()
        guard let agent = agent() else {
            finish(digest: digest, text: nil, now: now, note: "No hay un agente disponible: se muestra el resumen local.")
            return
        }
        let outputName = "\(key).md"
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(outputName))
        let run = AgentRun(provider: agent.provider,
                           scope: AgentScopeRef(kind: .course, folder: "weekly-summary", title: "Resumen semanal"),
                           prompt: WeeklySummaryPrompt.make(digest: digest, outputFile: outputName),
                           recipeID: nil, recipeTitle: "Resumen semanal", at: now)
        let request = AgentRequest(runID: run.id, provider: agent.provider, executablePath: agent.executable, cwd: directory,
                                   prompt: run.prompt, resumeSessionId: nil, options: agent.options)
        let useCase = self.useCase
        task = Task { [weak self] in
            let final = await useCase.execute(run: run, request: request) { _ in }
            await self?.completed(run: final, digest: digest, outputName: outputName)
        }
    }

    private func completed(run: AgentRun, digest: WeeklyDigest, outputName: String) {
        var text = (try? String(contentsOf: directory.appendingPathComponent(outputName), encoding: .utf8))
            .flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        if text == nil, run.status == .succeeded {
            text = run.transcript.reversed().compactMap { event -> String? in
                if case .result(let result) = event, !result.text.isEmpty { return result.text }
                return nil
            }.first
        }
        finish(digest: digest, text: text, now: .now,
               note: text == nil ? "El agente no produjo el resumen: se muestra el resumen local." : nil)
    }

    private func finish(digest: WeeklyDigest, text: String?, now: Date, note: String?) {
        let body = text ?? digest.markdown
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? body.write(to: file(for: digest.weekKey), atomically: true, encoding: .utf8)
        markdown = body
        state.latest = WeeklySummaryState.Record(weekKey: digest.weekKey, generatedAt: now, usedAgent: text != nil)
        state.dismissedWeekKey = nil
        message = note
        isGenerating = false
        persist()
        Task { [notifier] in
            await notifier?.notifyFinished(title: "Cátedra: resumen semanal",
                                           body: "Su resumen de la semana \(digest.weekKey) está listo en Hoy.")
        }
    }

    private func file(for weekKey: String) -> URL { directory.appendingPathComponent("\(weekKey).md") }

    private func persist() { try? store.save(state) }
}
