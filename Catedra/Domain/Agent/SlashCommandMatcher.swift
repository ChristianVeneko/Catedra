import Foundation

/// Ranks commands for a query. Tiers (best first): name prefix, alias prefix, word-boundary/substring on the name,
/// substring in the description, subsequence on the name. Case and diacritics are ignored.
enum SlashCommandMatcher {
    static func match(query: String, in commands: [SlashCommand], limit: Int) -> [SlashCommandMatch] {
        let q = fold(query)
        let ranked: [SlashCommandMatch]
        if q.isEmpty {
            ranked = commands.map { SlashCommandMatch(command: $0, score: 0, highlight: []) }
        } else {
            ranked = commands.compactMap { score($0, query: q) }
        }
        let sorted = ranked.sorted { a, b in
            if a.score != b.score { return a.score > b.score }
            if a.command.kind != b.command.kind { return order(a.command.kind) < order(b.command.kind) }
            if a.command.name.count != b.command.name.count { return a.command.name.count < b.command.name.count }
            return a.command.name < b.command.name
        }
        return Array(sorted.prefix(limit))
    }

    private static func order(_ kind: SlashCommand.Kind) -> Int {
        switch kind { case .app: 0; case .skill: 1; case .builtin: 2 }
    }

    private static func score(_ command: SlashCommand, query q: [String]) -> SlashCommandMatch? {
        let name = fold(command.name)
        if name.starts(with: q) {
            let exact = name.count == q.count ? 50 : 0
            return SlashCommandMatch(command: command, score: 1000 + exact, highlight: Array(0..<q.count))
        }
        if command.aliases.contains(where: { fold($0).starts(with: q) }) {
            return SlashCommandMatch(command: command, score: 800, highlight: [])
        }
        if let start = firstRange(of: q, in: name, boundaryOnly: true) {
            return SlashCommandMatch(command: command, score: 600, highlight: Array(start..<(start + q.count)))
        }
        if let start = firstRange(of: q, in: name, boundaryOnly: false) {
            return SlashCommandMatch(command: command, score: 500, highlight: Array(start..<(start + q.count)))
        }
        if firstRange(of: q, in: fold(command.description), boundaryOnly: false) != nil {
            return SlashCommandMatch(command: command, score: 300, highlight: [])
        }
        if q.count >= 2, let positions = subsequence(q, in: name) {
            return SlashCommandMatch(command: command, score: 100, highlight: positions)
        }
        return nil
    }

    /// Folds each character on its own so offsets stay aligned with the original string.
    static func fold(_ text: String) -> [String] {
        text.map { String($0).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
    }

    private static let separators: Set<String> = ["-", ":", "_", ".", "/", " "]

    private static func firstRange(of needle: [String], in hay: [String], boundaryOnly: Bool) -> Int? {
        guard !needle.isEmpty, hay.count >= needle.count else { return nil }
        for start in 0...(hay.count - needle.count) where Array(hay[start..<(start + needle.count)]) == needle {
            if !boundaryOnly || start == 0 || separators.contains(hay[start - 1]) { return start }
        }
        return nil
    }

    private static func subsequence(_ needle: [String], in hay: [String]) -> [Int]? {
        var positions: [Int] = []
        var i = 0
        for (index, char) in hay.enumerated() where i < needle.count && char == needle[i] {
            positions.append(index)
            i += 1
        }
        return i == needle.count ? positions : nil
    }
}
