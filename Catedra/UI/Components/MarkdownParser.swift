import Foundation

struct MarkdownListItem: Equatable {
    var depth: Int
    var ordered: Bool
    /// Display number of an ordered item (start number kept, then incremented per sibling).
    var number: Int?
    /// `nil` for a normal item; `true` / `false` for a `[x]` / `[ ]` task item.
    var checked: Bool?
    var text: String

    init(depth: Int = 0, ordered: Bool = false, number: Int? = nil, checked: Bool? = nil, text: String) {
        self.depth = depth; self.ordered = ordered; self.number = number; self.checked = checked; self.text = text
    }
}

enum MarkdownTableAlignment: Equatable {
    case none, left, center, right
}

enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case list(items: [MarkdownListItem])
    case code(String)
    case table(header: [String], alignments: [MarkdownTableAlignment], rows: [[String]])
    case image(alt: String, url: String)
    case quote(String)
    case rule
}

/// Minimal block-level Markdown parser; inline styling is delegated to `AttributedString(markdown:)`.
enum MarkdownParser {
    private struct Marker {
        var indent: Int
        var ordered: Bool
        var number: Int?
        var text: String
    }

    static func parse(_ source: String) -> [MarkdownBlock] {
        let lines = source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var paragraph = ""
        var i = 0
        /// Indent stack of a list interrupted by a fenced code block, so the list resumes at the same depth.
        var carriedStack: [Int]?

        func flushParagraph() {
            let text = paragraph.trimmingCharacters(in: .whitespaces)
            if !text.isEmpty { blocks.append(contentsOf: splitImages(text)) }
            paragraph = ""
        }

        while i < lines.count {
            let line = lines[i]
            let t = line.trimmingCharacters(in: .whitespaces)
            if !(t.isEmpty || fence(t) != nil || listMarker(line) != nil) { carriedStack = nil }

            if let open = fence(t) {
                flushParagraph()
                let fenceIndent = indent(of: line)
                var code: [String] = []
                i += 1
                while i < lines.count, !isClosingFence(lines[i], matching: open) {
                    code.append(stripIndent(lines[i], upTo: fenceIndent)); i += 1
                }
                blocks.append(.code(code.joined(separator: "\n")))
                i += 1; continue
            }
            if t.isEmpty { flushParagraph(); i += 1; continue }
            if let h = heading(t) { flushParagraph(); blocks.append(h); i += 1; continue }
            if isRule(t) { flushParagraph(); blocks.append(.rule); i += 1; continue }
            if let table = parseTable(lines, at: i) {
                flushParagraph()
                blocks.append(table.block); i = table.next; continue
            }
            if t.hasPrefix(">") {
                flushParagraph()
                var quote: [String] = []
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    var body = String(lines[i].trimmingCharacters(in: .whitespaces).dropFirst())
                    if body.hasPrefix(" ") { body.removeFirst() }
                    quote.append(body.trimmingCharacters(in: .whitespaces)); i += 1
                }
                blocks.append(.quote(quote.joined(separator: "\n"))); continue
            }
            if listMarker(line) != nil {
                flushParagraph()
                let list = parseList(lines, at: i, carried: carriedStack)
                blocks.append(.list(items: list.items))
                carriedStack = list.interruptedByFence ? list.stack : nil
                i = list.next; continue
            }
            let lead = leadingTrimmed(line)
            paragraph = paragraph.isEmpty ? lead : joinLines(paragraph, lead)
            i += 1
        }
        flushParagraph()
        return blocks
    }

    // MARK: Lists

    private static func parseList(_ lines: [String], at start: Int, carried: [Int]?) -> (items: [MarkdownListItem], next: Int, stack: [Int], interruptedByFence: Bool) {
        var items: [MarkdownListItem] = []
        var stack: [Int] = carried ?? []
        var counters: [Int: Int] = [:]
        var listOrdered: Bool?
        var i = start
        var fenced = false

        loop: while i < lines.count {
            let line = lines[i]
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty {
                var j = i
                while j < lines.count, lines[j].trimmingCharacters(in: .whitespaces).isEmpty { j += 1 }
                guard j < lines.count else { break loop }
                let next = lines[j]
                let nt = next.trimmingCharacters(in: .whitespaces)
                if fence(nt) != nil { fenced = indent(of: next) > 0 && !items.isEmpty; break loop }
                if listMarker(next) != nil || (indent(of: next) > 0 && !startsNewBlock(nt)) { i = j; continue }
                break loop
            }
            if fence(t) != nil { fenced = indent(of: line) > 0 && !items.isEmpty; break loop }
            if let m = listMarker(line), !isRule(t) {
                if listOrdered == nil { listOrdered = m.ordered }
                // A top-level switch between bullet and numbered markers starts a new list.
                if m.indent <= (stack.first ?? m.indent), m.ordered != listOrdered, !items.isEmpty { break loop }
                while let last = stack.last, last > m.indent { stack.removeLast() }
                if stack.last != m.indent { stack.append(m.indent) }
                let depth = stack.count - 1
                for key in counters.keys where key > depth { counters[key] = nil }
                var number: Int?
                if m.ordered {
                    number = counters[depth].map { $0 + 1 } ?? m.number ?? 1
                    counters[depth] = number
                } else {
                    counters[depth] = nil
                }
                var text = m.text
                var checked: Bool?
                for (prefix, value) in [("[ ] ", false), ("[x] ", true), ("[X] ", true)] where text.hasPrefix(prefix) {
                    checked = value; text = String(text.dropFirst(4)); break
                }
                items.append(MarkdownListItem(depth: depth, ordered: m.ordered, number: number, checked: checked, text: text))
                i += 1; continue
            }
            if startsNewBlock(t) || items.isEmpty { break loop }
            // Continuation (indented, or lazy right under an item) of the last item.
            items[items.count - 1].text = joinLines(items[items.count - 1].text, leadingTrimmed(line))
            i += 1
        }
        for k in items.indices { items[k].text = items[k].text.trimmingCharacters(in: .whitespaces) }
        return (items, i, stack, fenced)
    }

    private static func startsNewBlock(_ t: String) -> Bool {
        heading(t) != nil || isRule(t) || t.hasPrefix(">") || fence(t) != nil
    }

    private static func listMarker(_ line: String) -> Marker? {
        let ind = indent(of: line)
        let t = line.trimmingCharacters(in: .whitespaces)
        if t.count >= 1, "-*+".contains(t.first!), t.count == 1 || t.dropFirst().first == " " {
            if isRule(t) { return nil }
            return Marker(indent: ind, ordered: false, number: nil, text: String(t.dropFirst()).trimmingCharacters(in: .whitespaces))
        }
        let digits = t.prefix(while: { $0.isASCII && $0.isNumber })
        if !digits.isEmpty, digits.count <= 9 {
            let rest = t.dropFirst(digits.count)
            if let d = rest.first, d == "." || d == ")", rest.count == 1 || rest.dropFirst().first == " " {
                return Marker(indent: ind, ordered: true, number: Int(digits), text: String(rest.dropFirst()).trimmingCharacters(in: .whitespaces))
            }
        }
        return nil
    }

    // MARK: Leaf blocks

    private static func indent(of line: String) -> Int {
        var n = 0
        for c in line {
            if c == " " { n += 1 } else if c == "\t" { n += 4 } else { break }
        }
        return n
    }

    private static func leadingTrimmed(_ line: String) -> String {
        String(line.drop(while: { $0 == " " || $0 == "\t" }))
    }

    private static func stripIndent(_ line: String, upTo amount: Int) -> String {
        var removed = 0
        var result = Substring(line)
        while removed < amount, let c = result.first, c == " " { result.removeFirst(); removed += 1 }
        return String(result)
    }

    /// Opening fence (``` or ~~~, optional info string): its marker character and length.
    private static func fence(_ t: String) -> (char: Character, count: Int)? {
        guard let c = t.first, c == "`" || c == "~" else { return nil }
        let count = t.prefix(while: { $0 == c }).count
        guard count >= 3 else { return nil }
        if c == "`", t.dropFirst(count).contains("`") { return nil }
        return (c, count)
    }

    private static func isClosingFence(_ line: String, matching open: (char: Character, count: Int)) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        return t.count >= open.count && t.allSatisfy { $0 == open.char }
    }

    private static func isRule(_ t: String) -> Bool {
        let compact = t.filter { $0 != " " && $0 != "\t" }
        guard compact.count >= 3, let c = compact.first, "-*_".contains(c) else { return false }
        return compact.allSatisfy { $0 == c }
    }

    private static func heading(_ t: String) -> MarkdownBlock? {
        let hashes = t.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(hashes), t.dropFirst(hashes).first == " " else { return nil }
        var text = t.dropFirst(hashes).trimmingCharacters(in: .whitespaces)
        // Optional closing sequence: trailing #s separated by a space (or the whole text).
        let stripped = text.reversed().drop(while: { $0 == "#" })
        if stripped.count < text.count, stripped.isEmpty || stripped.first == " " {
            text = String(stripped.reversed()).trimmingCharacters(in: .whitespaces)
        }
        return .heading(level: hashes, text: text)
    }

    /// Joins two paragraph lines: a hard break (two trailing spaces or a backslash) keeps the newline, otherwise a space.
    private static func joinLines(_ previous: String, _ next: String) -> String {
        if previous.hasSuffix("\\") { return String(previous.dropLast()) + "\n" + next }
        if previous.hasSuffix("  ") {
            let trimmed = previous.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
            return trimmed + "\n" + next
        }
        return previous.trimmingCharacters(in: .whitespaces) + " " + next
    }

    // MARK: Tables

    private static func parseTable(_ lines: [String], at i: Int) -> (block: MarkdownBlock, next: Int)? {
        guard i + 1 < lines.count, lines[i].contains("|") else { return nil }
        let separator = lines[i + 1].trimmingCharacters(in: .whitespaces)
        guard separator.contains("|") else { return nil }
        let separatorCells = splitRow(separator)
        let alignments = separatorCells.compactMap(alignment)
        guard !separatorCells.isEmpty, alignments.count == separatorCells.count else { return nil }
        let header = splitRow(lines[i])
        guard header.count == alignments.count else { return nil }

        var rows: [[String]] = []
        var next = i + 2
        while next < lines.count {
            let t = lines[next].trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty, t.contains("|") else { break }
            var cells = splitRow(t)
            if cells.count > header.count { cells = Array(cells.prefix(header.count)) }
            while cells.count < header.count { cells.append("") }
            rows.append(cells)
            next += 1
        }
        return (.table(header: header, alignments: alignments, rows: rows), next)
    }

    private static func alignment(_ cell: String) -> MarkdownTableAlignment? {
        let c = cell.trimmingCharacters(in: .whitespaces)
        let core = c.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
        guard !core.isEmpty, core.allSatisfy({ $0 == "-" }), c.count - core.count <= 2 else { return nil }
        switch (c.hasPrefix(":"), c.hasSuffix(":")) {
        case (true, true): return .center
        case (true, false): return .left
        case (false, true): return .right
        default: return MarkdownTableAlignment.none
        }
    }

    /// Splits a row on unescaped pipes, ignoring one leading and one trailing pipe; `\|` becomes a literal pipe.
    private static func splitRow(_ row: String) -> [String] {
        var cells: [String] = []
        var current = ""
        var escaped = false
        for c in row.trimmingCharacters(in: .whitespaces) {
            if escaped {
                current += c == "|" ? "|" : "\\\(c)"
                escaped = false
            } else if c == "\\" {
                escaped = true
            } else if c == "|" {
                cells.append(current); current = ""
            } else {
                current.append(c)
            }
        }
        if escaped { current += "\\" }
        cells.append(current)
        var trimmed = cells.map { $0.trimmingCharacters(in: .whitespaces) }
        if row.trimmingCharacters(in: .whitespaces).hasPrefix("|"), !trimmed.isEmpty { trimmed.removeFirst() }
        if row.trimmingCharacters(in: .whitespaces).hasSuffix("|"), !row.trimmingCharacters(in: .whitespaces).hasSuffix("\\|"), !trimmed.isEmpty { trimmed.removeLast() }
        return trimmed
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
}
