import Testing
import Foundation
@testable import Catedra

struct AgentRunTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func makeRun() -> AgentRun {
        AgentRun(scope: AgentScopeRef(kind: .activity, folder: "08 - X/actividades/Tarea - A", title: "A"),
                 prompt: "Haz algo", recipeID: nil, recipeTitle: nil, at: t0)
    }

    @Test func newRunIsRunningWithUserPrompt() {
        let run = makeRun()
        #expect(run.status == .running)
        #expect(run.transcript == [.userPrompt("Haz algo")])
    }

    @Test func appliesInitAndSuccessfulResult() {
        var run = makeRun()
        run.apply(.initialized(sessionId: "s1", model: "haiku"), at: t0)
        run.apply(.assistantText("hola"), at: t0)
        run.apply(.result(AgentResult(isError: false, subtype: "success", text: "hola", sessionId: "s1", costUSD: 0.5, durationMs: 10)),
                  at: t0.addingTimeInterval(7))
        #expect(run.sessionId == "s1")
        #expect(run.model == "haiku")
        #expect(run.status == .succeeded)
        #expect(run.costUSD == 0.5)
        #expect(run.finishedAt == t0.addingTimeInterval(7))
        #expect(!run.transcript.contains { if case .initialized = $0 { true } else { false } })
    }

    @Test func errorResultFailsRun() {
        var run = makeRun()
        run.apply(.result(AgentResult(isError: true, subtype: "error_x", text: "", sessionId: nil, costUSD: nil, durationMs: nil)), at: t0)
        #expect(run.status == .failed)
    }

    @Test func runnerErrorFailsOnlyWhileRunning() {
        var run = makeRun()
        run.apply(.error("boom"), at: t0)
        #expect(run.status == .failed)
        var ok = makeRun()
        ok.apply(.result(AgentResult(isError: false, subtype: "success", text: "", sessionId: nil, costUSD: nil, durationMs: nil)), at: t0)
        ok.apply(.error("late"), at: t0)
        #expect(ok.status == .succeeded)
    }

    @Test func continuingStartsNewTurnAndAccumulatesCost() {
        var run = makeRun()
        run.apply(.initialized(sessionId: "s1", model: nil), at: t0)
        run.apply(.result(AgentResult(isError: false, subtype: "success", text: "", sessionId: "s1", costUSD: 0.2, durationMs: nil)), at: t0)
        run.beginTurn(prompt: "sigue", at: t0.addingTimeInterval(60))
        #expect(run.status == .running)
        #expect(run.finishedAt == nil)
        #expect(run.startedAt == t0)
        #expect(run.turnStartedAt == t0.addingTimeInterval(60))
        run.apply(.result(AgentResult(isError: false, subtype: "success", text: "", sessionId: "s1", costUSD: 0.3, durationMs: nil)), at: t0)
        #expect(abs(run.costUSD - 0.5) < 0.0001)
        #expect(run.transcript.contains(.userPrompt("sigue")))
    }

    @Test func cancelMarksCancelled() {
        var run = makeRun()
        run.finish(as: .cancelled, at: t0.addingTimeInterval(3))
        #expect(run.status == .cancelled)
        #expect(run.finishedAt == t0.addingTimeInterval(3))
    }

    @Test func titlePrefersRecipeThenPromptFirstLine() {
        var run = makeRun()
        #expect(run.title == "Haz algo")
        run = AgentRun(scope: run.scope, prompt: "linea1\nlinea2", recipeID: "r", recipeTitle: "Guía de estudio", at: t0)
        #expect(run.title == "Guía de estudio")
    }

    @Test func codableRoundTrip() throws {
        var run = makeRun()
        run.apply(.toolUse(id: "1", name: "Read", summary: "f"), at: t0)
        run.apply(.denials([PermissionDenial(toolName: "Bash", summary: "ls")]), at: t0)
        let data = try JSONEncoder().encode(run)
        #expect(try JSONDecoder().decode(AgentRun.self, from: data) == run)
    }

    @Test func transcriptItemsPairToolsAndAvoidDuplicateResultText() {
        let events: [AgentEvent] = [
            .userPrompt("p"),
            .thinking("t"),
            .toolUse(id: "1", name: "Read", summary: "a.md"),
            .toolResult(toolUseId: "1", isError: false, preview: "contenido"),
            .assistantText("respuesta"),
            .result(AgentResult(isError: false, subtype: "success", text: "respuesta", sessionId: nil, costUSD: nil, durationMs: nil)),
        ]
        let items = TranscriptItem.build(from: events)
        #expect(items.count == 4)
        if case .tool(_, let name, _, let result) = items[2] {
            #expect(name == "Read")
            #expect(result?.preview == "contenido")
        } else { Issue.record("expected tool item") }
    }

    @Test func transcriptShowsResultTextWhenNoAssistantTextInTurn() {
        let events: [AgentEvent] = [
            .userPrompt("p"),
            .result(AgentResult(isError: false, subtype: "success", text: "solo resultado", sessionId: nil, costUSD: nil, durationMs: nil)),
        ]
        let items = TranscriptItem.build(from: events)
        #expect(items.count == 2)
        if case .assistant(_, let text) = items[1] { #expect(text == "solo resultado") } else { Issue.record("expected assistant") }
    }
}
