import Foundation

enum DiffLineKind: String, Codable, Sendable { case unchanged, added, removed }

struct DiffLine: Equatable, Sendable {
    let kind: DiffLineKind
    let text: String
}

/// Line-based diff (longest common subsequence). Pure.
enum LineDiff {
    /// Above this many cells in the middle section the exact table is skipped and the section is shown as removed + added.
    static let maxCells = 1_000_000

    static func compare(old: String, new: String) -> [DiffLine] {
        diff(lines(of: old), lines(of: new))
    }

    static func lines(of text: String) -> [String] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var parts = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if parts.last == "" { parts.removeLast() }
        return parts
    }

    static func diff(_ a: [String], _ b: [String]) -> [DiffLine] {
        var prefix = 0
        while prefix < a.count, prefix < b.count, a[prefix] == b[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < a.count - prefix, suffix < b.count - prefix, a[a.count - 1 - suffix] == b[b.count - 1 - suffix] { suffix += 1 }
        let midA = Array(a[prefix..<(a.count - suffix)])
        let midB = Array(b[prefix..<(b.count - suffix)])

        var result = a[..<prefix].map { DiffLine(kind: .unchanged, text: $0) }
        result += middle(midA, midB)
        result += a[(a.count - suffix)...].map { DiffLine(kind: .unchanged, text: $0) }
        return result
    }

    private static func middle(_ a: [String], _ b: [String]) -> [DiffLine] {
        if a.isEmpty { return b.map { DiffLine(kind: .added, text: $0) } }
        if b.isEmpty { return a.map { DiffLine(kind: .removed, text: $0) } }
        guard a.count * b.count <= maxCells else {
            return a.map { DiffLine(kind: .removed, text: $0) } + b.map { DiffLine(kind: .added, text: $0) }
        }
        let width = b.count + 1
        var table = [Int](repeating: 0, count: (a.count + 1) * width)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                table[i * width + j] = a[i] == b[j] ? table[(i + 1) * width + j + 1] + 1
                    : max(table[(i + 1) * width + j], table[i * width + j + 1])
            }
        }
        var result: [DiffLine] = []
        var i = 0, j = 0
        while i < a.count, j < b.count {
            if a[i] == b[j] {
                result.append(DiffLine(kind: .unchanged, text: a[i])); i += 1; j += 1
            } else if table[(i + 1) * width + j] >= table[i * width + j + 1] {
                result.append(DiffLine(kind: .removed, text: a[i])); i += 1
            } else {
                result.append(DiffLine(kind: .added, text: b[j])); j += 1
            }
        }
        while i < a.count { result.append(DiffLine(kind: .removed, text: a[i])); i += 1 }
        while j < b.count { result.append(DiffLine(kind: .added, text: b[j])); j += 1 }
        return result
    }
}

extension Array where Element == DiffLine {
    var addedCount: Int { filter { $0.kind == .added }.count }
    var removedCount: Int { filter { $0.kind == .removed }.count }
    var hasChanges: Bool { contains { $0.kind != .unchanged } }
}

enum DiffRow: Equatable, Sendable {
    case line(DiffLine)
    /// `count` unchanged lines left out.
    case gap(count: Int)
}

extension LineDiff {
    /// Keeps changed lines plus `context` unchanged lines around them; longer runs collapse into a gap.
    static func condensed(_ lines: [DiffLine], context: Int = 2) -> [DiffRow] {
        var keep = [Bool](repeating: false, count: lines.count)
        for (i, line) in lines.enumerated() where line.kind != .unchanged {
            for j in max(0, i - context)...min(lines.count - 1, i + context) { keep[j] = true }
        }
        var rows: [DiffRow] = []
        var skipped = 0
        for (i, line) in lines.enumerated() {
            if keep[i] {
                if skipped > 0 { rows.append(.gap(count: skipped)); skipped = 0 }
                rows.append(.line(line))
            } else { skipped += 1 }
        }
        if skipped > 0 { rows.append(.gap(count: skipped)) }
        return rows
    }
}
