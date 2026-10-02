import Foundation

enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case list(ordered: Bool, items: [String])
    case code(String)
    case table(rows: [[String]])
    case image(alt: String, url: String)
    case quote(String)
    case rule
}

/// Minimal block-level Markdown parser; inline styling is delegated to `AttributedString(markdown:)`.
enum MarkdownParser {
    static func parse(_ source: String) -> [MarkdownBlock] {
        let lines = source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var i = 0

        func flushParagraph() {
            if !paragraph.isEmpty { blocks.append(contentsOf: splitImages(paragraph.joined(separator: " "))); paragraph = [] }
        }

        while i < lines.count {
            let line = lines[i]
            let t = line.trimmingCharacters(in: .whitespaces)

            if t.hasPrefix("```") {
                flushParagraph()
                var code: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") { code.append(lines[i]); i += 1 }
                blocks.append(.code(code.joined(separator: "\n")))
                i += 1; continue
            }
            if t.isEmpty { flushParagraph(); i += 1; continue }
            if let h = heading(t) { flushParagraph(); blocks.append(h); i += 1; continue }
            if t.count >= 3, Set(t).isSubset(of: ["-", "*", "_"]), Set(t).count == 1 {
                flushParagraph(); blocks.append(.rule); i += 1; continue
            }
            if t.hasPrefix("|") {
                flushParagraph()
                var rows: [[String]] = []
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    let row = lines[i].trimmingCharacters(in: .whitespaces)
                    let cells = row.split(separator: "|", omittingEmptySubsequences: false).dropFirst().dropLast()
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                    let isSeparator = !cells.isEmpty && cells.allSatisfy { $0.allSatisfy { "-: ".contains($0) } && $0.contains("-") }
                    if !isSeparator { rows.append(Array(cells)) }
                    i += 1
                }
                blocks.append(.table(rows: rows)); continue
            }
            if t.hasPrefix(">") {
                flushParagraph()
                var quote: [String] = []
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    quote.append(String(lines[i].trimmingCharacters(in: .whitespaces).dropFirst()).trimmingCharacters(in: .whitespaces)); i += 1
                }
                blocks.append(.quote(quote.joined(separator: " "))); continue
            }
            if let (ordered, _) = listMarker(t) {
                flushParagraph()
                var items: [String] = []
                while i < lines.count, let (o, text) = listMarker(lines[i].trimmingCharacters(in: .whitespaces)), o == ordered {
                    items.append(text); i += 1
                    // blank lines between items of the same list
                    var j = i
                    while j < lines.count, lines[j].trimmingCharacters(in: .whitespaces).isEmpty { j += 1 }
                    if j > i, j < lines.count, let (o2, _) = listMarker(lines[j].trimmingCharacters(in: .whitespaces)), o2 == ordered { i = j }
                }
                blocks.append(.list(ordered: ordered, items: items)); continue
            }
            paragraph.append(t)
            i += 1
        }
        flushParagraph()
        return blocks
    }

    private static func heading(_ t: String) -> MarkdownBlock? {
        let hashes = t.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(hashes), t.dropFirst(hashes).first == " " else { return nil }
        return .heading(level: hashes, text: t.dropFirst(hashes).trimmingCharacters(in: .whitespaces))
    }

    /// Splits a paragraph at its inline `![alt](url)` images: text runs stay paragraphs, each image becomes a block.
    static func splitImages(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var pending = ""
        var rest = Substring(text)
        func flushText() {
            let trimmed = pending.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { blocks.append(.paragraph(trimmed)) }
            pending = ""
        }
        while let start = rest.range(of: "![") {
            guard let mid = rest.range(of: "](", range: start.upperBound..<rest.endIndex),
                  !rest[start.upperBound..<mid.lowerBound].contains("]"),
                  let close = rest.range(of: ")", range: mid.upperBound..<rest.endIndex),
                  let url = imageURL(String(rest[mid.upperBound..<close.lowerBound])) else {
                pending += rest[rest.startIndex..<start.upperBound] // not an image: keep the marker as text
                rest = rest[start.upperBound...]
                continue
            }
            pending += rest[rest.startIndex..<start.lowerBound]
            flushText()
            blocks.append(.image(alt: String(rest[start.upperBound..<mid.lowerBound]), url: url))
            rest = rest[close.upperBound...]
        }
        pending += rest
        flushText()
        return blocks
    }

    /// URL part of an image: `<url with spaces>`, or `url "title"`.
    private static func imageURL(_ raw: String) -> String? {
        var t = raw.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("<"), let end = t.firstIndex(of: ">") { return String(t[t.index(after: t.startIndex)..<end]) }
        if let quote = t.firstIndex(of: "\""), t[..<quote].last == " " { t = String(t[..<quote]).trimmingCharacters(in: .whitespaces) }
        return t.isEmpty ? nil : t
    }

    private static func listMarker(_ t: String) -> (ordered: Bool, text: String)? {
        for m in ["- ", "* ", "+ "] where t.hasPrefix(m) { return (false, String(t.dropFirst(2)).trimmingCharacters(in: .whitespaces)) }
        let digits = t.prefix(while: \.isNumber)
        if !digits.isEmpty, t.dropFirst(digits.count).hasPrefix(". ") {
            return (true, String(t.dropFirst(digits.count + 2)).trimmingCharacters(in: .whitespaces))
        }
        return nil
    }
}
