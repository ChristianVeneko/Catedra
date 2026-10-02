import Testing
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
            .list(ordered: false, items: ["uno", "dos"]),
            .list(ordered: true, items: ["primero", "segundo"]),
        ])
    }

    @Test func parsesCodeAndTablesAndImages() {
        let md = "```\nlet x = 1\n```\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\n![alt](https://x/y.png)"
        let blocks = MarkdownParser.parse(md)
        #expect(blocks[0] == .code("let x = 1"))
        #expect(blocks[1] == .table(rows: [["a", "b"], ["1", "2"]]))
        #expect(blocks[2] == .image(alt: "alt", url: "https://x/y.png"))
    }

    @Test func joinsSoftWrappedParagraphLines() {
        #expect(MarkdownParser.parse("a\nb") == [.paragraph("a b")])
    }
}
