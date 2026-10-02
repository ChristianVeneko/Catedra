import Testing
import Foundation
@testable import Catedra

struct SlashTokenTests {
    @Test func detectsTokenAtStart() {
        let token = SlashToken.detect(in: "/res", caret: 4)
        #expect(token?.query == "res")
        #expect(token?.range == NSRange(location: 0, length: 4))
    }

    @Test func detectsTokenAfterWhitespaceAndNewline() {
        #expect(SlashToken.detect(in: "hola /mo", caret: 8)?.query == "mo")
        #expect(SlashToken.detect(in: "hola\n/mo", caret: 8)?.range == NSRange(location: 5, length: 3))
    }

    @Test func emptyQueryRightAfterSlash() {
        #expect(SlashToken.detect(in: "/", caret: 1)?.query == "")
    }

    @Test func ignoresSlashInsidePathsAndUrls() {
        #expect(SlashToken.detect(in: "mira @a/b", caret: 9) == nil)
        #expect(SlashToken.detect(in: "https://x", caret: 9) == nil)
    }

    @Test func noTokenWhenCaretPastWhitespace() {
        #expect(SlashToken.detect(in: "/model sonnet", caret: 13) == nil)
        #expect(SlashToken.detect(in: "/model ", caret: 7) == nil)
    }

    @Test func caretInMiddleUsesTextBeforeCaret() {
        let token = SlashToken.detect(in: "/compact", caret: 4)
        #expect(token?.query == "com")
        #expect(token?.range == NSRange(location: 0, length: 4))
    }

    @Test func replacingInsertsNameAndTrailingSpace() {
        let token = SlashToken.detect(in: "hola /mo", caret: 8)!
        let result = token.replacing(in: "hola /mo", with: "model")
        #expect(result.text == "hola /model ")
        #expect(result.caret == 12)
    }

    @Test func outOfRangeCaretIsSafe() {
        #expect(SlashToken.detect(in: "abc", caret: 99) == nil)
        #expect(SlashToken.detect(in: "", caret: 0) == nil)
    }
}
