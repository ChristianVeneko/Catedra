import Foundation

/// The `/query` fragment right before the caret that should open the command popup.
/// Offsets are UTF-16 (the unit `NSTextView` uses).
struct SlashToken: Equatable, Sendable {
    let query: String
    let range: NSRange

    /// A token starts with `/` at the beginning of the text or after whitespace and contains no whitespace up to the caret.
    static func detect(in text: String, caret: Int) -> SlashToken? {
        let ns = text as NSString
        guard caret >= 1, caret <= ns.length else { return nil }
        var i = caret - 1
        while i >= 0 {
            let char = ns.character(at: i)
            if isWhitespace(char) { return nil }
            if char == 0x2F { // "/"
                guard i == 0 || isWhitespace(ns.character(at: i - 1)) else { return nil }
                return SlashToken(query: ns.substring(with: NSRange(location: i + 1, length: caret - i - 1)),
                                  range: NSRange(location: i, length: caret - i))
            }
            i -= 1
        }
        return nil
    }

    /// Replaces the token with `/name ` and reports the new caret.
    func replacing(in text: String, with name: String) -> (text: String, caret: Int) {
        let insertion = "/\(name) "
        let result = (text as NSString).replacingCharacters(in: range, with: insertion)
        return (result, range.location + (insertion as NSString).length)
    }

    private static func isWhitespace(_ char: unichar) -> Bool {
        char == 0x20 || char == 0x0A || char == 0x09 || char == 0x0D
    }
}
