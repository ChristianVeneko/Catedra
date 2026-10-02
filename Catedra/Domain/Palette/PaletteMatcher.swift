import Foundation

/// Fuzzy ranking for the command palette. Same tiers as `SlashCommandMatcher` (title prefix, word boundary, substring,
/// secondary text, subsequence); case and diacritics are ignored. Every query word must match; the weakest word decides.
enum PaletteMatcher {
    static func fold(_ text: String) -> [Character] {
        Array(text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil))
    }

    static func tokens(_ query: String) -> [[Character]] {
        query.split(whereSeparator: \.isWhitespace).map { fold(String($0)) }.filter { !$0.isEmpty }
    }

    static func score(_ item: PaletteItem, tokens: [[Character]]) -> Int? {
        guard !tokens.isEmpty else { return 0 }
        var weakest = Int.max
        for token in tokens {
            guard let s = score(token, title: item.foldedTitle, extra: item.foldedExtra) else { return nil }
            weakest = min(weakest, s)
        }
        let whole = tokens.reduce([Character]()) { $0.isEmpty ? $1 : $0 + [" "] + $1 }
        return weakest + (item.foldedTitle == whole ? 50 : 0)
    }

    private static func score(_ token: [Character], title: [Character], extra: [Character]) -> Int? {
        if title.starts(with: token) { return 1000 }
        if firstRange(of: token, in: title, boundaryOnly: true) != nil { return 600 }
        if firstRange(of: token, in: title, boundaryOnly: false) != nil { return 500 }
        if firstRange(of: token, in: extra, boundaryOnly: false) != nil { return 300 }
        if token.count >= 2, isSubsequence(token, of: title) { return 100 }
        return nil
    }

    /// Ranked groups in fixed section order. An empty query yields the recents (or, with none, the first actions).
    static func results(query: String, items: [PaletteItem], recentIDs: [String] = []) -> [PaletteGroup] {
        let tokens = tokens(query)
        if tokens.isEmpty {
            let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let recents = recentIDs.compactMap { byID[$0] }.map { $0.withSection(.recents) }
            if !recents.isEmpty { return [PaletteGroup(section: .recents, items: Array(recents.prefix(PaletteSection.recents.limit)))] }
            let actions = items.filter { $0.section == .actions }
            return actions.isEmpty ? [] : [PaletteGroup(section: .actions, items: Array(actions.prefix(8)))]
        }
        var scored: [PaletteSection: [(item: PaletteItem, score: Int, index: Int)]] = [:]
        for (index, item) in items.enumerated() {
            guard let s = score(item, tokens: tokens) else { continue }
            scored[item.section, default: []].append((item, s, index))
        }
        return PaletteSection.allCases.compactMap { section in
            guard let rows = scored[section], !rows.isEmpty else { return nil }
            let top = rows.sorted { ($0.score, -$0.index) > ($1.score, -$1.index) }.prefix(section.limit).map(\.item)
            return PaletteGroup(section: section, items: Array(top))
        }
    }

    private static let separators: Set<Character> = ["-", ":", "_", ".", "/", " ", "(", "·"]

    private static func firstRange(of needle: [Character], in hay: [Character], boundaryOnly: Bool) -> Int? {
        guard !needle.isEmpty, hay.count >= needle.count else { return nil }
        for start in 0...(hay.count - needle.count) where hay[start..<(start + needle.count)].elementsEqual(needle) {
            if !boundaryOnly || start == 0 || separators.contains(hay[start - 1]) { return start }
        }
        return nil
    }

    private static func isSubsequence(_ needle: [Character], of hay: [Character]) -> Bool {
        var i = 0
        for char in hay where i < needle.count && char == needle[i] { i += 1 }
        return i == needle.count
    }
}

extension PaletteItem {
    func withSection(_ section: PaletteSection) -> PaletteItem {
        PaletteItem(id: id, section: section, title: title, subtitle: subtitle, symbol: symbol, action: action, courseFolder: courseFolder)
    }
}
