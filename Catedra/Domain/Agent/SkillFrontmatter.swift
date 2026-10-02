import Foundation

/// Minimal YAML-frontmatter reader for `SKILL.md` and command files (`name`, `description`, `argument-hint`).
enum SkillFrontmatter {
    struct Metadata: Equatable, Sendable {
        var name: String?
        var description: String?
        var argumentHint: String?
    }

    static func parse(_ text: String) -> Metadata {
        var lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")[...]
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return Metadata() }
        lines = lines.dropFirst()
        var fields: [String: String] = [:]
        var currentKey: String?
        var blockStyle = false
        var block: [String] = []

        func flush() {
            if let key = currentKey, blockStyle { fields[key] = block.joined(separator: " ") }
            block = []; blockStyle = false; currentKey = nil
        }

        for line in lines {
            if line.trimmingCharacters(in: .whitespaces) == "---" { break }
            if blockStyle, line.first == " " || line.first == "\t" || line.isEmpty {
                let piece = line.trimmingCharacters(in: .whitespaces)
                if !piece.isEmpty { block.append(piece) }
                continue
            }
            flush()
            guard let colon = line.firstIndex(of: ":"), !line.hasPrefix(" ") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            currentKey = key
            if [">", "|", ">-", "|-", ">+", "|+"].contains(value) {
                blockStyle = true
            } else {
                fields[key] = unquote(value)
            }
        }
        flush()
        return Metadata(name: nonEmpty(fields["name"]), description: nonEmpty(fields["description"]),
                        argumentHint: nonEmpty(fields["argument-hint"] ?? fields["argumentHint"]))
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private static func unquote(_ value: String) -> String {
        guard value.count >= 2, let first = value.first, let last = value.last,
              (first == "\"" && last == "\"") || (first == "'" && last == "'") else { return value }
        return String(value.dropFirst().dropLast())
    }
}
