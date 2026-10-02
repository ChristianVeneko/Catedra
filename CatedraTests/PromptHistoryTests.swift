import Testing
import Foundation
@testable import Catedra

struct PromptHistoryTests {
    @Test func cyclesBackAndForthRestoringDraft() {
        var history = PromptHistory(entries: ["uno", "dos", "tres"])
        #expect(history.previous(current: "borrador") == "tres")
        #expect(history.previous(current: "tres") == "dos")
        #expect(history.previous(current: "dos") == "uno")
        #expect(history.previous(current: "uno") == "uno") // clamps at the oldest
        #expect(history.next() == "dos")
        #expect(history.next() == "tres")
        #expect(history.next() == "borrador")
        #expect(history.next() == nil) // already at the draft
    }

    @Test func emptyHistoryDoesNothing() {
        var history = PromptHistory(entries: [])
        #expect(history.previous(current: "x") == nil)
        #expect(history.next() == nil)
    }

    @Test func recordResetsCursorAndSkipsConsecutiveDuplicates() {
        var history = PromptHistory(entries: ["a"])
        _ = history.previous(current: "")
        history.record("b")
        history.record("b")
        #expect(history.entries == ["a", "b"])
        #expect(history.previous(current: "") == "b")
    }

    @Test func entriesFromRunsSkipRecipeTemplatesAndKeepOrder() {
        let scope = AgentScopeRef(kind: .course, folder: "c", title: "C")
        var first = AgentRun(scope: scope, prompt: "primero", recipeID: nil, recipeTitle: nil, at: Date(timeIntervalSince1970: 1))
        first.beginTurn(prompt: "segundo", at: Date(timeIntervalSince1970: 2))
        let recipe = AgentRun(scope: scope, prompt: "PLANTILLA LARGA", recipeID: "r", recipeTitle: "Receta", at: Date(timeIntervalSince1970: 3))
        let entries = PromptHistory.entries(from: [recipe, first]) // any order in
        #expect(entries == ["primero", "segundo"])
    }
}
