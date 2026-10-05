import Testing
import Foundation
@testable import Catedra

struct PasteFilePathsTests {
    private let existing: Set<String> = [
        "/Users/x/Pegado 04.png", "/Users/x/a.png", "/Users/x/b.pdf", "/Users/x/Docs/c.txt", "/Users/x/it's.txt",
    ]
    private func paths(_ text: String) -> [String]? {
        PasteClassifier.filePaths(in: text, home: "/Users/x", fileExists: { existing.contains($0) })?.map(\.path)
    }

    @Test func absolutePath() { #expect(paths("/Users/x/a.png") == ["/Users/x/a.png"]) }
    @Test func tildePath() { #expect(paths("~/Docs/c.txt") == ["/Users/x/Docs/c.txt"]) }
    @Test func quotedPaths() {
        #expect(paths("'/Users/x/Pegado 04.png'") == ["/Users/x/Pegado 04.png"])
        #expect(paths("\"/Users/x/Pegado 04.png\"") == ["/Users/x/Pegado 04.png"])
    }
    @Test func backslashEscapedSpaces() { #expect(paths("/Users/x/Pegado\\ 04.png") == ["/Users/x/Pegado 04.png"]) }
    @Test func unescapedSpacesInSinglePath() { #expect(paths("/Users/x/Pegado 04.png") == ["/Users/x/Pegado 04.png"]) }
    @Test func fileURLPercentEncoded() { #expect(paths("file:///Users/x/Pegado%2004.png") == ["/Users/x/Pegado 04.png"]) }
    @Test func onePerLine() { #expect(paths("/Users/x/a.png\n\n/Users/x/b.pdf\n") == ["/Users/x/a.png", "/Users/x/b.pdf"]) }
    @Test func whitespaceSeparatedTokens() {
        #expect(paths("/Users/x/a.png /Users/x/b.pdf") == ["/Users/x/a.png", "/Users/x/b.pdf"])
        #expect(paths("/Users/x/Pegado\\ 04.png '/Users/x/a.png'") == ["/Users/x/Pegado 04.png", "/Users/x/a.png"])
    }
    @Test func mixedLineKeepsTextPaste() {
        #expect(paths("/Users/x/a.png\nhola mundo") == nil)
        #expect(paths("mira /Users/x/a.png") == nil)
    }
    @Test func missingFileOrPlainTextIsNotFiles() {
        #expect(paths("/Users/x/nope.png") == nil)
        #expect(paths("hola") == nil)
        #expect(paths("   \n ") == nil)
        #expect(paths("relative/a.png") == nil)
    }
}
