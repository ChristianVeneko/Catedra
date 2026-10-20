import Foundation

/// Converts a chat message's Markdown into clipboard formats: plain text (tables tab-separated for spreadsheets)
/// and HTML (for Word, Pages, Notion). Built on the same blocks `MarkdownView` renders.
enum MarkdownExport {
    static func plainText(_ source: String) -> String {
        MarkdownParser.parse(source).map(plainText(of:)).joined(separator: "\n\n")
    }

    static func html(_ source: String) -> String {
        let body = MarkdownParser.parse(source).map(html(of:)).joined(separator: "\n")
        return "<html><head><meta charset=\"utf-8\"></head><body>\(body)</body></html>"
    }

    // MARK: - Plain text

    private static func plainText(of block: MarkdownBlock) -> String {
        switch block {
        case .heading(_, let text), .paragraph(let text):
            return plainInline(text)
        case .list(let items):
            return items.map { item in
                String(repeating: "    ", count: item.depth) + marker(item) + plainInline(item.text)
            }.joined(separator: "\n")
        case .code(let code):
            return code
        case .table(let header, _, let rows):
            return ([header] + rows).map { $0.map(plainInline).joined(separator: "\t") }.joined(separator: "\n")
        case .image(let alt, _):
            return alt
        case .quote(let text):
            return plainInline(text)
        case .rule:
            return "———"
        }
    }

    private static func marker(_ item: MarkdownListItem) -> String {
        if let checked = item.checked { return checked ? "☑ " : "☐ " }
        if item.ordered { return "\(item.number ?? 1). " }
        return "• "
    }

    private static func plainInline(_ text: String) -> String {
        guard let attributed = attributed(text) else { return text }
        return String(attributed.characters)
    }

    // MARK: - HTML

    private static func html(of block: MarkdownBlock) -> String {
        switch block {
        case .heading(let level, let text):
            let tag = "h\(min(max(level, 1), 6))"
            return "<\(tag)>\(htmlInline(text))</\(tag)>"
        case .paragraph(let text):
            return "<p>\(htmlInline(text))</p>"
        case .list(let items):
            return htmlList(items)
        case .code(let code):
            return "<pre><code>\(escape(code))</code></pre>"
        case .table(let header, _, let rows):
            let head = "<tr>" + header.map { "<th>\(htmlInline($0))</th>" }.joined() + "</tr>"
            let body = rows.map { "<tr>" + $0.map { "<td>\(htmlInline($0))</td>" }.joined() + "</tr>" }.joined()
            return "<table border=\"1\" cellpadding=\"4\" style=\"border-collapse:collapse\">\(head)\(body)</table>"
        case .image(let alt, let url):
            return "<img alt=\"\(escape(alt))\" src=\"\(escape(url))\">"
        case .quote(let text):
            return "<blockquote>\(htmlInline(text))</blockquote>"
        case .rule:
            return "<hr>"
        }
    }

    /// Nests `<ul>` / `<ol>` by item depth; a deeper item opens a list inside the previous `<li>`.
    private static func htmlList(_ items: [MarkdownListItem]) -> String {
        var out = ""
        var open: [String] = []  // list tags currently open, outermost first
        for item in items {
            let tag = item.ordered ? "ol" : "ul"
            let depth = min(item.depth, open.count)
            if depth < open.count {
                while open.count > depth + 1 { out += "</li></\(open.removeLast())>" }
                if open.last == tag {
                    out += "</li>"
                } else {
                    out += "</li></\(open.removeLast())><\(tag)>"
                    open.append(tag)
                }
            } else {
                out += "<\(tag)>"
                open.append(tag)
            }
            let box = item.checked.map { $0 ? "☑ " : "☐ " } ?? ""
            out += "<li>\(box)\(htmlInline(item.text))"
        }
        while let tag = open.popLast() { out += "</li></\(tag)>" }
        return out
    }

    private static func htmlInline(_ text: String) -> String {
        guard let attributed = attributed(text) else { return escape(text) }
        var out = ""
        for run in attributed.runs {
            var piece = escape(String(attributed[run.range].characters))
            let intent = run.inlinePresentationIntent ?? []
            if intent.contains(.code) { piece = "<code>\(piece)</code>" }
            if intent.contains(.strikethrough) { piece = "<s>\(piece)</s>" }
            if intent.contains(.emphasized) { piece = "<em>\(piece)</em>" }
            if intent.contains(.stronglyEmphasized) { piece = "<strong>\(piece)</strong>" }
            if let link = run.link { piece = "<a href=\"\(escape(link.absoluteString))\">\(piece)</a>" }
            out += piece
        }
        return out
    }

    private static func attributed(_ text: String) -> AttributedString? {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return try? AttributedString(markdown: text, options: options)
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
