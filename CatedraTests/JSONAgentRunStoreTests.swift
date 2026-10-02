import Testing
import Foundation
@testable import Catedra

struct JSONAgentRunStoreTests {
    func run(_ folder: String, at seconds: TimeInterval, prompt: String = "p") -> AgentRun {
        AgentRun(scope: AgentScopeRef(kind: .activity, folder: folder, title: "t"), prompt: prompt, recipeID: nil, recipeTitle: nil,
                 at: Date(timeIntervalSince1970: 1_800_000_000 + seconds))
    }

    @Test func roundTripPreservesRun() throws {
        let dir = try makeTempDirectory()
        let store = JSONAgentRunStore(directory: dir)
        var r = run("c/a", at: 0)
        r.apply(.initialized(sessionId: "s", model: "haiku"), at: r.startedAt)
        r.apply(.assistantText("hola"), at: r.startedAt)
        r.apply(.result(AgentResult(isError: false, subtype: "success", text: "hola", sessionId: "s", costUSD: 0.01, durationMs: 5)),
                at: r.startedAt.addingTimeInterval(2))
        try store.save(r)
        let loaded = store.loadAll()
        #expect(loaded == [r])
    }

    @Test func saveOverwritesSameRun() throws {
        let store = JSONAgentRunStore(directory: try makeTempDirectory())
        var r = run("c/a", at: 0)
        try store.save(r)
        r.apply(.assistantText("x"), at: r.startedAt)
        try store.save(r)
        #expect(store.loadAll().count == 1)
        #expect(store.loadAll().first?.transcript.count == 2)
    }

    @Test func capsRunsPerScopeKeepingNewest() throws {
        let store = JSONAgentRunStore(directory: try makeTempDirectory(), maxRunsPerScope: 3)
        for i in 0..<5 { try store.save(run("c/a", at: Double(i), prompt: "p\(i)")) }
        try store.save(run("c/other", at: 0))
        let all = store.loadAll()
        let a = all.filter { $0.scope.folder == "c/a" }
        #expect(a.map(\.prompt) == ["p4", "p3", "p2"])
        #expect(all.filter { $0.scope.folder == "c/other" }.count == 1)
    }

    @Test func deleteRemovesRun() throws {
        let store = JSONAgentRunStore(directory: try makeTempDirectory())
        let r = run("c/a", at: 0)
        try store.save(r)
        store.delete(id: r.id)
        #expect(store.loadAll().isEmpty)
    }

    @Test func missingDirectoryYieldsEmpty() {
        let store = JSONAgentRunStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("nope-\(UUID())"))
        #expect(store.loadAll().isEmpty)
    }

    @Test func ignoresCorruptFiles() throws {
        let dir = try makeTempDirectory()
        try "not json".write(to: dir.appendingPathComponent("bad.json"), atomically: true, encoding: .utf8)
        let store = JSONAgentRunStore(directory: dir)
        try store.save(run("c/a", at: 0))
        #expect(store.loadAll().count == 1)
    }
}
