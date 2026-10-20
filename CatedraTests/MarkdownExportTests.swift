import Testing
import Foundation
@testable import Catedra

struct MarkdownExportTests {
    @Test func plainTextStripsInlineMarkupAndKeepsStructure() {
        let md = """
        # Título

        Texto con **negrita** y `código`.

        - uno
          - anidado
        1. primero
        - [x] hecho
        """
        #expect(MarkdownExport.plainText(md) == """
        Título

        Texto con negrita y código.

        • uno
            • anidado

        1. primero

        ☑ hecho
        """)
    }

    @Test func plainTextTablesUseTabsForSpreadsheets() {
        let md = """
        | Materia | Nota |
        |---|---:|
        | **Redes** | 18 |
        """
        #expect(MarkdownExport.plainText(md) == "Materia\tNota\nRedes\t18")
    }

    @Test func plainTextKeepsCodeQuoteAndRule() {
        let md = """
        ```swift
        let a = **1**
        ```

        > cita *suave*

        ---
        """
        #expect(MarkdownExport.plainText(md) == "let a = **1**\n\ncita suave\n\n———")
    }

    @Test func htmlRendersHeadingsAndInlineStyles() {
        let html = MarkdownExport.html("## Hola\n\nTexto **fuerte**, *suave*, `x<y` y [web](https://a.com).")
        #expect(html.contains("<h2>Hola</h2>"))
        #expect(html.contains("<p>Texto <strong>fuerte</strong>, <em>suave</em>, <code>x&lt;y</code> y <a href=\"https://a.com\">web</a>.</p>"))
    }

    @Test func htmlNestsListsByDepth() {
        let html = MarkdownExport.html("- uno\n  - dos\n- tres\n\n1. a\n2. b")
        #expect(html.contains("<ul><li>uno<ul><li>dos</li></ul></li><li>tres</li></ul>"))
        #expect(html.contains("<ol><li>a</li><li>b</li></ol>"))
    }

    @Test func htmlRendersTablesAndEscapesCode() {
        let html = MarkdownExport.html("| A | B |\n|---|---|\n| 1 | **2** |\n\n```\n<div>&</div>\n```")
        #expect(html.contains("<table"))
        #expect(html.contains("<th>A</th><th>B</th>"))
        #expect(html.contains("<td>1</td><td><strong>2</strong></td>"))
        #expect(html.contains("<pre><code>&lt;div&gt;&amp;&lt;/div&gt;</code></pre>"))
    }
}
