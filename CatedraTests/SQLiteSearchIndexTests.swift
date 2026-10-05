import Testing
import Foundation
@testable import Catedra

struct SQLiteSearchIndexTests {
    func makeStore() throws -> SQLiteSearchIndex {
        try SQLiteSearchIndex(file: makeTempDirectory().appendingPathComponent("search.sqlite"))
    }

    func stamp(_ m: Int64 = 1) -> FileStamp { FileStamp(modified: m, size: 100) }

    @Test func insertsAndFindsIgnoringAccentsAndCase() async throws {
        let store = try makeStore()
        try await store.replace(path: "01 - X/contenidos/a.md", stamp: stamp(),
                                pages: [IndexedPage(page: 0, text: "El Autómata Finito Determinístico acepta lenguajes regulares.")])
        for query in ["automata", "AUTÓMATA", "determinist", "regulares"] {
            let match = try #require(SearchQuerySanitizer.matchExpression(from: query))
            let hits = try await store.search(match: match, limit: 10)
            #expect(hits.map(\.path) == ["01 - X/contenidos/a.md"], "query \(query)")
        }
        let none = try await store.search(match: "\"inexistente\"*", limit: 10)
        #expect(none.isEmpty)
    }

    @Test func snippetMarksTheMatchAndKeepsThePage() async throws {
        let store = try makeStore()
        try await store.replace(path: "c/a.pdf", stamp: stamp(), pages: [
            IndexedPage(page: 1, text: "Introducción general."),
            IndexedPage(page: 2, text: "Las máquinas de Turing son el modelo universal de cómputo."),
        ])
        let hits = try await store.search(match: "\"turing\"*", limit: 5)
        #expect(hits.count == 1)
        #expect(hits[0].page == 2)
        let segments = SnippetParser.segments(from: hits[0].snippet)
        #expect(segments.contains(SnippetSegment(text: "Turing", isMatch: true)))
    }

    @Test func prefixMatchingAndRawSyntaxNeverThrow() async throws {
        let store = try makeStore()
        try await store.replace(path: "c/a.md", stamp: stamp(), pages: [IndexedPage(page: 0, text: "complejidad computacional")])
        let prefix = try await store.search(match: "\"complej\"*", limit: 5)
        #expect(prefix.count == 1)
        for raw in ["AND OR", "\"unbalanced", "a:b*", "((", "NEAR(", "-x", "*"] {
            if let match = SearchQuerySanitizer.matchExpression(from: raw) {
                _ = try await store.search(match: match, limit: 5)
            }
        }
    }

    @Test func replaceOverwritesAndRemoveDeletes() async throws {
        let store = try makeStore()
        try await store.replace(path: "c/a.md", stamp: stamp(1), pages: [IndexedPage(page: 0, text: "alfa beta")])
        try await store.replace(path: "c/a.md", stamp: stamp(2), pages: [IndexedPage(page: 0, text: "gamma delta")])
        #expect(try await store.search(match: "\"alfa\"", limit: 5).isEmpty)
        #expect(try await store.search(match: "\"gamma\"", limit: 5).count == 1)
        #expect(try await store.stamps() == ["c/a.md": stamp(2)])
        try await store.remove(paths: ["c/a.md"])
        #expect(try await store.search(match: "\"gamma\"", limit: 5).isEmpty)
        #expect(try await store.stamps().isEmpty)
    }

    @Test func fileWithoutTextIsStillTracked() async throws {
        let store = try makeStore()
        try await store.replace(path: "c/scan.pdf", stamp: stamp(), pages: [])
        #expect(try await store.stamps().keys.contains("c/scan.pdf"))
    }

    @Test func persistsAcrossInstances() async throws {
        let file = try makeTempDirectory().appendingPathComponent("s.sqlite")
        let first = try SQLiteSearchIndex(file: file)
        try await first.replace(path: "c/a.md", stamp: stamp(), pages: [IndexedPage(page: 0, text: "persistente")])
        let second = try SQLiteSearchIndex(file: file)
        #expect(try await second.search(match: "\"persistente\"", limit: 5).count == 1)
    }

    @Test func changingTheWorkspaceRootClearsTheIndex() async throws {
        let store = try makeStore()
        try await store.ensureRoot("/ws/one")
        try await store.replace(path: "c/a.md", stamp: stamp(), pages: [IndexedPage(page: 0, text: "alfa")])
        try await store.ensureRoot("/ws/one")
        #expect(try await store.stamps().count == 1)
        try await store.ensureRoot("/ws/two")
        #expect(try await store.stamps().isEmpty)
        #expect(try await store.search(match: "\"alfa\"", limit: 5).isEmpty)
    }
}

struct ContentIndexingUseCaseTests {
    final class Recorder: @unchecked Sendable {
        var extracted: [String] = []
    }

    struct FakeScanner: ContentFileScanning {
        var files: [String: FileStamp]
        func scan(root: URL, courses: [Course]) -> [String: FileStamp] { files }
    }

    struct FakeExtractor: ContentTextExtracting {
        let recorder: Recorder
        func pages(at url: URL, kind: IndexedFileKind) -> [IndexedPage] {
            recorder.extracted.append(url.lastPathComponent)
            return [IndexedPage(page: 0, text: "texto de \(url.lastPathComponent)")]
        }
    }

    @Test func reindexesOnlyChangedFilesAndDropsRemovedOnes() async throws {
        let store = try SQLiteSearchIndex(file: makeTempDirectory().appendingPathComponent("s.sqlite"))
        let recorder = Recorder()
        let root = URL(fileURLWithPath: "/ws")
        let course = try #require(Course(folderName: "01 - X"))
        func run(_ files: [String: FileStamp]) async throws -> IndexingReport {
            try await ContentIndexingUseCase(store: store, scanner: FakeScanner(files: files), extractor: FakeExtractor(recorder: recorder))
                .run(root: root, courses: [course])
        }
        let s1 = FileStamp(modified: 1, size: 1)
        let first = try await run(["01 - X/a.md": s1, "01 - X/b.md": s1])
        #expect(first == IndexingReport(added: 2, changed: 0, removed: 0))
        #expect(Set(recorder.extracted) == ["a.md", "b.md"])

        recorder.extracted = []
        let second = try await run(["01 - X/a.md": s1, "01 - X/b.md": FileStamp(modified: 2, size: 1), "01 - X/c.md": s1])
        #expect(second == IndexingReport(added: 1, changed: 1, removed: 0))
        #expect(Set(recorder.extracted) == ["b.md", "c.md"])

        recorder.extracted = []
        let third = try await run(["01 - X/b.md": FileStamp(modified: 2, size: 1)])
        #expect(third == IndexingReport(added: 0, changed: 0, removed: 2))
        #expect(recorder.extracted.isEmpty)
        #expect(try await store.search(match: "\"a\"", limit: 5).isEmpty)
        #expect(try await store.stamps().keys.sorted() == ["01 - X/b.md"])
    }
}
