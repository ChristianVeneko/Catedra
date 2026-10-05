import Testing
import Foundation
@testable import Catedra

struct MarkdownParserTests {
    @Test func parsesHeadingsParagraphsAndLists() {
        let md = """
        # Titulo

        Texto con **negrita**.

        - uno
        - dos

        1. primero
        2. segundo
        """
        let blocks = MarkdownParser.parse(md)
        #expect(blocks == [
            .heading(level: 1, text: "Titulo"),
            .paragraph("Texto con **negrita**."),
            .list(items: [.init(text: "uno"), .init(text: "dos")]),
            .list(items: [.init(ordered: true, number: 1, text: "primero"), .init(ordered: true, number: 2, text: "segundo")]),
        ])
    }

    @Test func parsesCodeAndTablesAndImages() {
        let md = "```\nlet x = 1\n```\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\n![alt](https://x/y.png)"
        let blocks = MarkdownParser.parse(md)
        #expect(blocks[0] == .code("let x = 1"))
        #expect(blocks[1] == .table(header: ["a", "b"], alignments: [.none, .none], rows: [["1", "2"]]))
        #expect(blocks[2] == .image(alt: "alt", url: "https://x/y.png"))
    }

    @Test func joinsSoftWrappedParagraphLines() {
        #expect(MarkdownParser.parse("a\nb") == [.paragraph("a b")])
    }

    @Test func splitsConsecutiveInlineImagesIntoTwoImages() {
        let blocks = MarkdownParser.parse("![a](_imagenes/x.jpg)![b](https://cdn.example.com/y.jpg)")
        #expect(blocks == [
            .image(alt: "a", url: "_imagenes/x.jpg"),
            .image(alt: "b", url: "https://cdn.example.com/y.jpg"),
        ])
    }

    @Test func splitsImagesOutOfAParagraphKeepingTextOrder() {
        let blocks = MarkdownParser.parse("Mira esto ![fig](_imagenes/a.png) y luego\n![](b.png) fin.")
        #expect(blocks == [
            .paragraph("Mira esto"),
            .image(alt: "fig", url: "_imagenes/a.png"),
            .paragraph("y luego"),
            .image(alt: "", url: "b.png"),
            .paragraph("fin."),
        ])
    }

    @Test func imageUrlsMayContainEncodedSpacesAndTitles() {
        #expect(MarkdownParser.parse("![a](_imagenes/a%20b.jpg \"titulo\")") == [.image(alt: "a", url: "_imagenes/a%20b.jpg")])
        #expect(MarkdownParser.parse("![a](<_imagenes/a b.jpg>)") == [.image(alt: "a", url: "_imagenes/a b.jpg")])
    }

    @Test func linksAndBrokenImageSyntaxStayText() {
        #expect(MarkdownParser.parse("[x](y.png) y ![sin cierre](a.png") == [.paragraph("[x](y.png) y ![sin cierre](a.png")])
    }

    @Test func imageSourceResolution() {
        let base = URL(fileURLWithPath: "/ws/curso/actividad", isDirectory: true)
        #expect(MarkdownImageSource.resolve("_imagenes/a%20b.jpg", relativeTo: base) == .local(URL(fileURLWithPath: "/ws/curso/actividad/_imagenes/a b.jpg")))
        #expect(MarkdownImageSource.resolve("https://x.org/y.png", relativeTo: base) == .remote(URL(string: "https://x.org/y.png")!))
        #expect(MarkdownImageSource.resolve("/tmp/z.png", relativeTo: base) == .local(URL(fileURLWithPath: "/tmp/z.png")))
        #expect(MarkdownImageSource.resolve("a.png", relativeTo: nil) == .unresolved)
        #expect(MarkdownImageSource.resolve("", relativeTo: base) == .unresolved)
        #expect(MarkdownImageSource.resolve("data:image/png;base64,AAA", relativeTo: base) == .unresolved)
    }

    // MARK: Tables

    @Test func tableAlignmentsAndInlineCells() {
        let md = "| Nombre | Centro | Der |\n|:---|:---:|---:|\n| **a** | `b` | [c](https://x) |"
        #expect(MarkdownParser.parse(md) == [.table(
            header: ["Nombre", "Centro", "Der"], alignments: [.left, .center, .right],
            rows: [["**a**", "`b`", "[c](https://x)"]])])
    }

    @Test func tableWithoutEdgePipes() {
        let md = "a | b\n--- | ---\n1 | 2\n3 | 4"
        #expect(MarkdownParser.parse(md) == [.table(header: ["a", "b"], alignments: [.none, .none], rows: [["1", "2"], ["3", "4"]])])
    }

    @Test func tableEscapedPipesAndRaggedRows() {
        let md = "| a | b | c |\n|---|---|---|\n| x \\| y | z |\n| 1 | 2 | 3 | 4 |"
        #expect(MarkdownParser.parse(md) == [.table(
            header: ["a", "b", "c"], alignments: [.none, .none, .none],
            rows: [["x | y", "z", ""], ["1", "2", "3"]])])
    }

    @Test func tableEndsAtBlankLineAndParagraphFollows() {
        let blocks = MarkdownParser.parse("| a |\n|---|\n| 1 |\n\nfin")
        #expect(blocks == [.table(header: ["a"], alignments: [.none], rows: [["1"]]), .paragraph("fin")])
    }

    @Test func pipeLineWithoutSeparatorIsParagraph() {
        #expect(MarkdownParser.parse("a | b\nc") == [.paragraph("a | b c")])
    }

    // MARK: Lists

    @Test func nestedListsKeepDepth() {
        let md = "- **Alfabeto (Σ):**\n  - c: confirmar o publicar\n  - p: pago parcial\n- **Estado inicial:** q0"
        #expect(MarkdownParser.parse(md) == [.list(items: [
            .init(depth: 0, text: "**Alfabeto (Σ):**"),
            .init(depth: 1, text: "c: confirmar o publicar"),
            .init(depth: 1, text: "p: pago parcial"),
            .init(depth: 0, text: "**Estado inicial:** q0"),
        ])])
    }

    @Test func threeLevelsAndMixedOrderedNesting() {
        let md = "1. uno\n   - a\n     - x\n2. dos"
        #expect(MarkdownParser.parse(md) == [.list(items: [
            .init(depth: 0, ordered: true, number: 1, text: "uno"),
            .init(depth: 1, text: "a"),
            .init(depth: 2, text: "x"),
            .init(depth: 0, ordered: true, number: 2, text: "dos"),
        ])])
    }

    @Test func orderedListKeepsStartNumberAndParenMarker() {
        #expect(MarkdownParser.parse("3. a\n4. b") == [.list(items: [
            .init(ordered: true, number: 3, text: "a"), .init(ordered: true, number: 4, text: "b")])])
        #expect(MarkdownParser.parse("1) a\n2) b") == [.list(items: [
            .init(ordered: true, number: 1, text: "a"), .init(ordered: true, number: 2, text: "b")])])
    }

    @Test func taskItems() {
        #expect(MarkdownParser.parse("- [ ] pendiente\n- [x] hecho\n- [X] otro") == [.list(items: [
            .init(checked: false, text: "pendiente"), .init(checked: true, text: "hecho"), .init(checked: true, text: "otro")])])
    }

    @Test func continuationLinesJoinTheItem() {
        #expect(MarkdownParser.parse("- uno\n  sigue\n- dos") == [.list(items: [.init(text: "uno sigue"), .init(text: "dos")])])
    }

    @Test func blankLinesBetweenItemsKeepOneList() {
        #expect(MarkdownParser.parse("- a\n\n- b\n\n  - c") == [.list(items: [
            .init(text: "a"), .init(text: "b"), .init(depth: 1, text: "c")])])
    }

    @Test func listEndsBeforeParagraphAfterBlankLine() {
        #expect(MarkdownParser.parse("- a\n\nTexto") == [.list(items: [.init(text: "a")]), .paragraph("Texto")])
    }

    @Test func indentedFenceInsideListItemResumesAtSameDepth() {
        let md = "1. paso\n   ```swift\n   let x = 1\n   ```\n2. otro"
        #expect(MarkdownParser.parse(md) == [
            .list(items: [.init(ordered: true, number: 1, text: "paso")]),
            .code("let x = 1"),
            .list(items: [.init(ordered: true, number: 2, text: "otro")]),
        ])
    }

    // MARK: Leaf blocks

    @Test func fencesWithLanguageAndTilde() {
        #expect(MarkdownParser.parse("``` swift\nlet x = 1\n```") == [.code("let x = 1")])
        #expect(MarkdownParser.parse("~~~python\nprint(1)\n~~~\n\nfin") == [.code("print(1)"), .paragraph("fin")])
        #expect(MarkdownParser.parse("````\n```\ninner\n```\n````") == [.code("```\ninner\n```")])
    }

    @Test func headingsDropClosingHashes() {
        #expect(MarkdownParser.parse("## Titulo ##") == [.heading(level: 2, text: "Titulo")])
        #expect(MarkdownParser.parse("# C#") == [.heading(level: 1, text: "C#")])
    }

    @Test func rulesInAllForms() {
        #expect(MarkdownParser.parse("---\n***\n___\n- - -") == [.rule, .rule, .rule, .rule])
    }

    @Test func hardLineBreaks() {
        #expect(MarkdownParser.parse("a  \nb") == [.paragraph("a\nb")])
        #expect(MarkdownParser.parse("a\\\nb") == [.paragraph("a\nb")])
    }

    @Test func blockquoteKeepsLineBreaks() {
        #expect(MarkdownParser.parse("> uno\n> - dos\n> tres") == [.quote("uno\n- dos\ntres")])
    }
}
