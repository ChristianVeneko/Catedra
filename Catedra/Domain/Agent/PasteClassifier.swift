import Foundation

/// What a paste in the composer should do, decided from the pasteboard's contents.
enum PasteContent: Equatable {
    /// Files copied in Finder: insert their paths and attach them.
    case files([URL])
    /// Image data only (e.g. a screenshot): save it and attach the saved file.
    case image
    /// Anything else: the normal text paste.
    case text
}

enum PasteClassifier {
    /// Files win (Finder also puts an icon and the name on the pasteboard); an image counts only when there is no text
    /// (rich text copied from documents often carries a rendering of itself).
    static func classify(fileURLs: [URL], hasImage: Bool, hasText: Bool) -> PasteContent {
        if !fileURLs.isEmpty { return .files(fileURLs) }
        if hasImage, !hasText { return .image }
        return .text
    }
}

extension PasteClassifier {
    /// File URLs when pasted TEXT consists solely of paths to existing files; nil for a normal text paste.
    /// Accepts absolute and `~/` paths, single/double quotes, Terminal-style backslash-escaped spaces and `file://` URLs,
    /// one per line (or whitespace-separated when each token resolves). Every non-empty line must resolve.
    static func filePaths(in text: String, home: String = NSHomeDirectory(), fileExists: (String) -> Bool) -> [URL]? {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: CharacterSet.newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return nil }
        var urls: [URL] = []
        for line in lines {
            if let url = resolve(line, home: home, fileExists: fileExists) { urls.append(url); continue }
            let tokens = shellTokens(line)
            guard !tokens.isEmpty else { return nil }
            for token in tokens {
                guard let url = resolve(token, home: home, fileExists: fileExists, unescape: false) else { return nil }
                urls.append(url)
            }
        }
        return urls
    }

    private static func resolve(_ raw: String, home: String, fileExists: (String) -> Bool, unescape: Bool = true) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }
        if s.count >= 2, let f = s.first, let l = s.last, f == l, f == "\"" || f == "'" {
            s = String(s.dropFirst().dropLast())
        } else if unescape {
            s = unescapeBackslashes(s)
        }
        if s.lowercased().hasPrefix("file://") {
            guard let url = URL(string: s), url.isFileURL else { return nil }
            s = url.path
        } else if s == "~" {
            s = home
        } else if s.hasPrefix("~/") {
            s = (home as NSString).appendingPathComponent(String(s.dropFirst(2)))
        }
        guard s.hasPrefix("/"), fileExists(s) else { return nil }
        return URL(fileURLWithPath: s)
    }

    private static func unescapeBackslashes(_ s: String) -> String {
        var out = ""
        var escaped = false
        for c in s {
            if escaped { out.append(c); escaped = false } else if c == "\\" { escaped = true } else { out.append(c) }
        }
        if escaped { out.append("\\") }
        return out
    }

    /// Shell-like split on unquoted, unescaped whitespace. Quotes and escapes are already resolved in the returned tokens.
    private static func shellTokens(_ line: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var quote: Character?
        var escaped = false
        for c in line {
            if escaped { current.append(c); escaped = false; continue }
            if c == "\\", quote != "'" {
                escaped = true; continue
            }
            if let q = quote {
                if c == q { quote = nil } else { current.append(c) }
                continue
            }
            if c == "\"" || c == "'" { quote = c; continue }
            if c == " " || c == "\t" {
                if !current.isEmpty { tokens.append(current); current = "" }
                continue
            }
            current.append(c)
        }
        if quote != nil { return [] }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }
}
