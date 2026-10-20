import Foundation

/// Reads a script Markdown file:
/// optional frontmatter (`titulo`, `duracion`, `idioma`), `##` sections, paragraphs or bullets of spoken text,
/// and `[cue]` stage directions. Inline emphasis is stripped; sentences end at `.`, `!`, `?`, `…`, a bullet or a blank line.
enum ScriptParser {
    static func parse(_ source: String, fallbackTitle: String = "Guion") -> Script {
        var builder = Builder()
        var lines = source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        let meta = frontmatter(&lines)
        var h1: String?

        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { builder.endParagraph(); continue }
            if line.hasPrefix("## ") || line.hasPrefix("### ") {
                builder.startSection(String(line.drop { $0 == "#" }).trimmingCharacters(in: .whitespaces))
                continue
            }
            if line.hasPrefix("# ") {
                if h1 == nil { h1 = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces) }
                continue
            }
            if let bullet = bulletText(line) {
                builder.endParagraph()
                builder.add(bullet)
                builder.endParagraph()
                continue
            }
            builder.add(line)
        }
        builder.finish()

        let title = meta["titulo"] ?? meta["title"] ?? h1 ?? fallbackTitle
        return Script(title: title,
                      language: meta["idioma"] ?? meta["language"],
                      targetDuration: (meta["duracion"] ?? meta["duration"]).flatMap(duration),
                      sections: builder.sections,
                      sentences: builder.sentences,
                      words: builder.words)
    }

    /// "3m", "3 min", "90s", "2m30s", "1:30" or a bare number of minutes. Nil when unreadable.
    static func duration(_ text: String) -> TimeInterval? {
        let t = text.lowercased().trimmingCharacters(in: .whitespaces)
        if let colon = t.firstIndex(of: ":"), let m = Double(t[..<colon]), let s = Double(t[t.index(after: colon)...]) {
            return m * 60 + s
        }
        if let minutes = Double(t) { return minutes * 60 }
        var total: TimeInterval = 0
        var matched = false
        for (pattern, factor) in [(#"(\d+)\s*h"#, 3600.0), (#"(\d+)\s*m(?!s)"#, 60.0), (#"(\d+)\s*s"#, 1.0)] {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)),
                  let range = Range(match.range(at: 1), in: t), let value = Double(t[range]) else { continue }
            total += value * factor
            matched = true
        }
        return matched ? total : nil
    }

    // MARK: - Internals

    private static func frontmatter(_ lines: inout [String]) -> [String: String] {
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
              let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) else { return [:] }
        var meta: [String: String] = [:]
        for line in lines[1..<end] {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if !value.isEmpty { meta[Script.normalize(key)] = value }
        }
        lines.removeSubrange(0...end)
        return meta
    }

    private static func bulletText(_ line: String) -> String? {
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) { return String(line.dropFirst(2)) }
        if let dot = line.firstIndex(where: { $0 == "." || $0 == ")" }), line[..<dot].allSatisfy(\.isNumber),
           !line[..<dot].isEmpty, line[line.index(after: dot)...].first == " " {
            return String(line[line.index(dot, offsetBy: 2)...])
        }
        return nil
    }

    private struct Builder {
        var sections: [Script.Section] = []
        var sentences: [Script.Sentence] = []
        var words: [Script.Word] = []
        private var sectionTitle: String?
        private var sectionStart = 0
        private var open: [Script.Token] = []
        private var openWords: [String] = []
        private var pendingCues: [String] = []

        mutating func startSection(_ title: String) {
            endParagraph()
            closeSection()
            sectionTitle = title
        }

        mutating func add(_ line: String) {
            for piece in Self.pieces(line) {
                switch piece {
                case .cue(let cue):
                    if open.isEmpty { pendingCues.append(cue) } else { open.append(.cue(cue)) }
                case .text(let text):
                    for raw in text.split(whereSeparator: \.isWhitespace) {
                        let display = Self.stripEmphasis(String(raw))
                        let normalized = Script.normalize(display)
                        guard !normalized.isEmpty else { continue }
                        if open.isEmpty { open = pendingCues.map(Script.Token.cue); pendingCues = [] }
                        open.append(.word(words.count))
                        openWords.append(display)
                        words.append(Script.Word(text: display, normalized: normalized, sentence: sentences.count))
                        if Self.endsSentence(display) { closeSentence() }
                    }
                }
            }
        }

        mutating func endParagraph() {
            closeSentence()
            if !pendingCues.isEmpty, !sentences.isEmpty, sentences.count > sectionStart {
                sentences[sentences.count - 1].tokens += pendingCues.map(Script.Token.cue)
            }
            pendingCues = []
        }

        mutating func finish() {
            endParagraph()
            closeSection()
        }

        private mutating func closeSentence() {
            guard !openWords.isEmpty else { return }
            sentences.append(Script.Sentence(section: sectionIndex, tokens: open, text: openWords.joined(separator: " ")))
            open = []
            openWords = []
        }

        private var sectionIndex: Int { sections.count }

        private mutating func closeSection() {
            if sentences.count > sectionStart || sectionTitle != nil {
                sections.append(Script.Section(title: sectionTitle ?? "", sentences: sectionStart..<sentences.count))
            }
            sectionStart = sentences.count
        }

        private enum Piece { case text(String), cue(String) }

        private static let cuePattern = try! NSRegularExpression(pattern: #"\[([^\[\]]+)\]"#)

        private static func pieces(_ line: String) -> [Piece] {
            var result: [Piece] = []
            var cursor = line.startIndex
            for match in cuePattern.matches(in: line, range: NSRange(line.startIndex..., in: line)) {
                guard let whole = Range(match.range, in: line), let inner = Range(match.range(at: 1), in: line) else { continue }
                if cursor < whole.lowerBound { result.append(.text(String(line[cursor..<whole.lowerBound]))) }
                result.append(.cue(line[inner].trimmingCharacters(in: .whitespaces).lowercased()))
                cursor = whole.upperBound
            }
            if cursor < line.endIndex { result.append(.text(String(line[cursor...]))) }
            return result
        }

        private static func stripEmphasis(_ word: String) -> String {
            word.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "__", with: "")
                .replacingOccurrences(of: "*", with: "").replacingOccurrences(of: "`", with: "")
        }

        private static func endsSentence(_ word: String) -> Bool {
            let trimmed = word.trimmingCharacters(in: CharacterSet(charactersIn: "\"'”’)»"))
            guard let last = trimmed.last else { return false }
            return ".!?…".contains(last)
        }
    }
}
