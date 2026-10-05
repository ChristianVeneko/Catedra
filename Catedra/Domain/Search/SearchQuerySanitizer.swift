import Foundation

/// Turns free user text into a safe FTS5 `MATCH` expression. Pure.
///
/// Every run of letters/digits becomes a quoted token (so operators such as `OR`, `NOT`, `NEAR`, column filters, `^`, `*`
/// or stray quotes are plain words), tokens are implicitly AND-ed, and the last token is a prefix match unless the user
/// already typed a trailing space.
enum SearchQuerySanitizer {
    static let maxTokens = 8

    static func matchExpression(from query: String) -> String? {
        let normalized = query.precomposedStringWithCanonicalMapping
        let tokens = normalized
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .prefix(maxTokens)
        guard !tokens.isEmpty else { return nil }
        let endsWithSeparator = normalized.unicodeScalars.last.map { !CharacterSet.alphanumerics.contains($0) } ?? false
        return tokens.enumerated().map { index, token in
            let quoted = "\"\(token)\""
            return index == tokens.count - 1 && !endsWithSeparator ? quoted + "*" : quoted
        }.joined(separator: " ")
    }
}
