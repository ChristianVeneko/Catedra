import Testing
import Foundation
@testable import Catedra

struct SearchQuerySanitizerTests {
    @Test func quotesTokensAndPrefixesTheLastOne() {
        #expect(SearchQuerySanitizer.matchExpression(from: "autómata finito") == "\"autómata\" \"finito\"*")
    }

    @Test func trailingSpaceMeansTheLastWordIsComplete() {
        #expect(SearchQuerySanitizer.matchExpression(from: "autómata finito ") == "\"autómata\" \"finito\"")
    }

    @Test func rawFTSSyntaxIsNeutralized() {
        #expect(SearchQuerySanitizer.matchExpression(from: "a OR b NOT \"c\" NEAR(d)") == "\"a\" \"OR\" \"b\" \"NOT\" \"c\" \"NEAR\" \"d\"")
        #expect(SearchQuerySanitizer.matchExpression(from: "col:x* ^y -z") == "\"col\" \"x\" \"y\" \"z\"*")
        let expression = SearchQuerySanitizer.matchExpression(from: "\"\"\" ' ) ( * : ")
        #expect(expression == nil)
    }

    @Test func emptyOrSymbolOnlyQueriesYieldNil() {
        #expect(SearchQuerySanitizer.matchExpression(from: "") == nil)
        #expect(SearchQuerySanitizer.matchExpression(from: "   ") == nil)
        #expect(SearchQuerySanitizer.matchExpression(from: "!!! ---") == nil)
    }

    @Test func keepsDigitsAndComposesAccents() {
        #expect(SearchQuerySanitizer.matchExpression(from: "ley 2da") == "\"ley\" \"2da\"*")
        let decomposed = "cafe\u{301}"
        #expect(SearchQuerySanitizer.matchExpression(from: decomposed) == "\"café\"*")
    }

    @Test func limitsTheNumberOfTokens() {
        let query = (1...20).map { "w\($0)" }.joined(separator: " ")
        let expression = SearchQuerySanitizer.matchExpression(from: query) ?? ""
        #expect(expression.split(separator: " ").count == SearchQuerySanitizer.maxTokens)
    }
}

struct SearchIndexPolicyTests {
    @Test func indexesPDFMarkdownAndText() {
        #expect(SearchIndexPolicy.kind(forRelativePath: "01 - X/contenidos/Unidad I/tema.pdf") == .pdf)
        #expect(SearchIndexPolicy.kind(forRelativePath: "01 - X/contenidos/Unidad I/_texto.md") == .text)
        #expect(SearchIndexPolicy.kind(forRelativePath: "01 - X/actividades/Tarea/enunciado.md") == .text)
        #expect(SearchIndexPolicy.kind(forRelativePath: "01 - X/foros/Cartelera.md") == .text)
        #expect(SearchIndexPolicy.kind(forRelativePath: "01 - X/actividades/Tarea/apuntes/notas.txt") == .text)
        #expect(SearchIndexPolicy.kind(forRelativePath: "01 - X/NOTA.PDF") == .pdf)
    }

    @Test func skipsSystemAndImageFolders() {
        #expect(SearchIndexPolicy.kind(forRelativePath: "_sistema/data/readme.md") == nil)
        #expect(SearchIndexPolicy.kind(forRelativePath: "01 - X/contenidos/U/_imagenes/a.md") == nil)
        #expect(SearchIndexPolicy.kind(forRelativePath: "01 - X/_sistema/notas.md") == nil)
    }

    @Test func skipsBinaryAndHiddenFiles() {
        for name in ["a.png", "a.jpg", "a.docx", "a.zip", "a.py", "a.pyc", "a", ".DS_Store", ".hidden.md"] {
            #expect(SearchIndexPolicy.kind(forRelativePath: "01 - X/contenidos/\(name)") == nil)
        }
        #expect(SearchIndexPolicy.kind(forRelativePath: "01 - X/.git/notes.md") == nil)
    }

    @Test func descendsOnlyIntoVisibleFolders() {
        #expect(SearchIndexPolicy.shouldDescend(into: "contenidos"))
        #expect(!SearchIndexPolicy.shouldDescend(into: "_imagenes"))
        #expect(!SearchIndexPolicy.shouldDescend(into: "_sistema"))
        #expect(!SearchIndexPolicy.shouldDescend(into: ".git"))
    }

    @Test func enforcesSizeLimits() {
        #expect(SearchIndexPolicy.isWithinSizeLimit(.pdf, bytes: 10_000_000))
        #expect(!SearchIndexPolicy.isWithinSizeLimit(.pdf, bytes: SearchIndexPolicy.maxPDFBytes + 1))
        #expect(!SearchIndexPolicy.isWithinSizeLimit(.text, bytes: SearchIndexPolicy.maxTextBytes + 1))
    }
}

struct IndexDiffTests {
    func stamp(_ m: Int64, _ s: Int64 = 10) -> FileStamp { FileStamp(modified: m, size: s) }

    @Test func detectsAddedChangedAndRemoved() {
        let stored = ["a": stamp(1), "b": stamp(1), "c": stamp(1)]
        let current = ["a": stamp(1), "b": stamp(2), "d": stamp(1)]
        let diff = IndexDiff.compute(stored: stored, current: current)
        #expect(diff.added == ["d"])
        #expect(diff.changed == ["b"])
        #expect(diff.removed == ["c"])
        #expect(diff.toIndex == ["b", "d"])
        #expect(!diff.isEmpty)
    }

    @Test func sizeChangeCountsAsChange() {
        let diff = IndexDiff.compute(stored: ["a": stamp(1, 10)], current: ["a": stamp(1, 11)])
        #expect(diff.changed == ["a"])
    }

    @Test func identicalSnapshotsAreEmpty() {
        let both = ["a": stamp(1), "b": stamp(2)]
        #expect(IndexDiff.compute(stored: both, current: both).isEmpty)
    }
}

struct SnippetParserTests {
    @Test func splitsMarkedMatches() {
        let raw = "…el \(SnippetParser.open)autómata\(SnippetParser.close) finito\nes \(SnippetParser.open)útil\(SnippetParser.close)"
        #expect(SnippetParser.segments(from: raw) == [
            SnippetSegment(text: "…el ", isMatch: false), SnippetSegment(text: "autómata", isMatch: true),
            SnippetSegment(text: " finito es ", isMatch: false), SnippetSegment(text: "útil", isMatch: true),
        ])
    }

    @Test func plainTextIsOneSegment() {
        #expect(SnippetParser.segments(from: "sin marcas") == [SnippetSegment(text: "sin marcas", isMatch: false)])
        #expect(SnippetParser.segments(from: "").isEmpty)
    }

    @Test func unbalancedMarkersDoNotCrash() {
        let raw = "a \(SnippetParser.open)b"
        #expect(SnippetParser.segments(from: raw).map(\.text).joined() == "a b")
    }
}

struct ContentSearchHitTests {
    let root = URL(fileURLWithPath: "/ws")

    func hit(_ path: String, page: Int? = nil) -> ContentSearchHit {
        ContentSearchHit(raw: RawSearchHit(path: path, page: page ?? 0, snippet: "x"), root: root)
    }

    @Test func derivesCourseAndAbsoluteURL() {
        let h = hit("01 - Autómatas/contenidos/U1/tema.pdf", page: 3)
        #expect(h.courseFolder == "01 - Autómatas")
        #expect(h.url.path == "/ws/01 - Autómatas/contenidos/U1/tema.pdf")
        #expect(h.page == 3)
        #expect(h.fileName == "tema.pdf")
        #expect(hit("01 - A/x.md").page == nil)
    }

    @Test func diversifyCapsPerFileAndTotal() {
        let hits = [hit("c/a.pdf", page: 1), hit("c/a.pdf", page: 2), hit("c/a.pdf", page: 3), hit("c/b.md"), hit("c/c.md")]
        let shown = ContentSearchHit.diversified(hits, perFile: 2, total: 4)
        #expect(shown.map(\.id) == [hits[0].id, hits[1].id, hits[3].id, hits[4].id])
    }

    @Test func attachmentTargetUsesUniqueFilesAndDominantCourse() {
        let hits = [hit("c1/a.pdf", page: 1), hit("c1/a.pdf", page: 2), hit("c2/b.md"), hit("c2/d.md"), hit("c1/e.md")]
        let target = ContentSearchHit.attachmentTarget(for: hits, maxFiles: 4)
        #expect(target?.courseFolder == "c1")
        #expect(target?.files.map(\.lastPathComponent) == ["a.pdf", "b.md", "d.md", "e.md"])
        #expect(ContentSearchHit.attachmentTarget(for: [], maxFiles: 4) == nil)
    }
}

struct PaletteContentHitTests {
    @Test func buildsFullTextRowsWithPageSnippetAndAction() throws {
        let course = try #require(Course(folderName: "01 - Autómatas"))
        let raw = RawSearchHit(path: "01 - Autómatas/contenidos/tema.pdf", page: 4, snippet: "x \(SnippetParser.open)y\(SnippetParser.close)")
        let hit = ContentSearchHit(raw: raw, root: URL(fileURLWithPath: "/ws"))
        let items = PaletteCatalog.contentHitItems([hit], courses: [course])
        #expect(items.count == 1)
        #expect(items[0].section == .fullText)
        #expect(items[0].title == "tema.pdf · p. 4")
        #expect(items[0].subtitle == "Autómatas")
        #expect(items[0].snippet == raw.snippet)
        #expect(items[0].action == .openContentHit(courseFolder: "01 - Autómatas", path: "/ws/01 - Autómatas/contenidos/tema.pdf", page: 4))
        #expect(items[0].withSection(.recents).snippet == raw.snippet)
    }
}
