import Foundation

/// Drives one agent turn: streams events from the runner into the run, persists it and resolves the final status.
struct RunAgentUseCase: Sendable {
    let runner: AgentRunning
    let store: AgentRunStoring
    var now: @Sendable () -> Date = { .now }

    /// Runs `request` against `run`, calling `onUpdate` after every change. Returns the final run.
    func execute(run initial: AgentRun, request: AgentRequest,
                 onUpdate: @Sendable (AgentRun) async -> Void) async -> AgentRun {
        var run = initial
        try? store.save(run)
        await onUpdate(run)
        do {
            for try await event in runner.start(request) {
                run.apply(event, at: now())
                await onUpdate(run)
            }
            if run.status == .running {
                run.apply(.error("El agente terminó sin entregar un resultado."), at: now())
            }
        } catch AgentRunnerError.cancelled {
            run.finish(as: .cancelled, at: now())
        } catch is CancellationError {
            run.finish(as: .cancelled, at: now())
        } catch {
            run.apply(.error(error.localizedDescription), at: now())
        }
        try? store.save(run)
        await onUpdate(run)
        return run
    }

    func cancel(runID: UUID) { runner.cancel(runID: runID) }
}
