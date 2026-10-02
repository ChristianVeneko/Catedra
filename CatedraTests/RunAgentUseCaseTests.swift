import Testing
import Foundation
@testable import Catedra

private final class FakeRunner: AgentRunning, @unchecked Sendable {
    let script: [AgentEvent]
    let failure: Error?
    init(_ script: [AgentEvent], failure: Error? = nil) { self.script = script; self.failure = failure }
    func start(_ request: AgentRequest) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { c in
            for e in script { c.yield(e) }
            c.finish(throwing: failure)
        }
    }
    func cancel(runID: UUID) {}
}

private final class MemoryStore: AgentRunStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var saved: [AgentRun] = []
    func save(_ run: AgentRun) throws { lock.lock(); saved.append(run); lock.unlock() }
    func loadAll() -> [AgentRun] { lock.lock(); defer { lock.unlock() }; return saved }
    func delete(id: UUID) {}
}

struct RunAgentUseCaseTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func fixture() -> (AgentRun, AgentRequest) {
        let run = AgentRun(scope: AgentScopeRef(kind: .course, folder: "01 - X", title: "X"), prompt: "p", recipeID: nil, recipeTitle: nil, at: t0)
        let request = AgentRequest(runID: run.id, executablePath: "/x", cwd: URL(fileURLWithPath: "/tmp"), prompt: "p",
                                   resumeSessionId: nil, options: AgentOptions())
        return (run, request)
    }

    func ok() -> AgentResult { AgentResult(isError: false, subtype: "success", text: "t", sessionId: "s", costUSD: 0.1, durationMs: 1) }

    @Test func succeedsAndPersists() async {
        let (run, request) = fixture()
        let store = MemoryStore()
        let useCase = RunAgentUseCase(runner: FakeRunner([.initialized(sessionId: "s", model: nil), .assistantText("t"), .result(ok())]),
                                      store: store, now: { Date(timeIntervalSince1970: 1_800_000_010) })
        let final = await useCase.execute(run: run, request: request, onUpdate: { _ in })
        #expect(final.status == .succeeded)
        #expect(final.sessionId == "s")
        #expect(store.loadAll().last?.status == .succeeded)
    }

    @Test func cancellationMarksCancelled() async {
        let (run, request) = fixture()
        let useCase = RunAgentUseCase(runner: FakeRunner([.assistantText("a")], failure: AgentRunnerError.cancelled), store: MemoryStore())
        let final = await useCase.execute(run: run, request: request, onUpdate: { _ in })
        #expect(final.status == .cancelled)
        #expect(final.finishedAt != nil)
    }

    @Test func endingWithoutResultFails() async {
        let (run, request) = fixture()
        let useCase = RunAgentUseCase(runner: FakeRunner([.assistantText("a")]), store: MemoryStore())
        let final = await useCase.execute(run: run, request: request, onUpdate: { _ in })
        #expect(final.status == .failed)
    }

    @Test func runnerErrorEventFails() async {
        let (run, request) = fixture()
        let useCase = RunAgentUseCase(runner: FakeRunner([.error("boom")]), store: MemoryStore())
        let final = await useCase.execute(run: run, request: request, onUpdate: { _ in })
        #expect(final.status == .failed)
        #expect(final.transcript.contains(.error("boom")))
    }
}
