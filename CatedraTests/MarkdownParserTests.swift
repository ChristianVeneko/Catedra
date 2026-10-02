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
}
