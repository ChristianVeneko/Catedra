import Testing
import Foundation
@testable import Catedra

struct ScopeRelativePathTests {
    private let base = URL(fileURLWithPath: "/w/curso", isDirectory: true)

    @Test func relativeReferenceInsideScope() {
        #expect(ScopeRelativePath.reference(for: URL(fileURLWithPath: "/w/curso/material/a.pdf"), in: base) == "@material/a.pdf")
    }

    @Test func spacesAreQuoted() {
        #expect(ScopeRelativePath.reference(for: URL(fileURLWithPath: "/w/curso/mi material/a b.pdf"), in: base) == "@\"mi material/a b.pdf\"")
    }

    @Test func outsideScopeIsRejected() {
        #expect(ScopeRelativePath.reference(for: URL(fileURLWithPath: "/w/otro/a.pdf"), in: base) == nil)
        #expect(ScopeRelativePath.reference(for: URL(fileURLWithPath: "/w/curso-2/a.pdf"), in: base) == nil)
        #expect(ScopeRelativePath.reference(for: base, in: base) == nil)
    }

    @Test func insertionAddsSeparatorsOnlyWhenNeeded() {
        #expect(ScopeRelativePath.insert(["@a", "@b"], into: "revisa", at: 6).text == "revisa @a @b ")
        #expect(ScopeRelativePath.insert(["@a"], into: "", at: 0).text == "@a ")
        #expect(ScopeRelativePath.insert(["@a"], into: "x ", at: 2).text == "x @a ")
        let r = ScopeRelativePath.insert(["@a"], into: "ab cd", at: 2)
        #expect(r.text == "ab @a  cd" || r.text == "ab @a cd")
    }

    // MARK: Attachments from anywhere

    @Test func attachmentInsideScopeStaysRelative() {
        #expect(ScopeRelativePath.attachment(for: URL(fileURLWithPath: "/w/curso/material/a.pdf"), in: base) == "@material/a.pdf")
    }

    @Test func attachmentOutsideScopeUsesAbsolutePath() {
        #expect(ScopeRelativePath.attachment(for: URL(fileURLWithPath: "/Users/x/Desktop/a.png"), in: base) == "@/Users/x/Desktop/a.png")
        #expect(ScopeRelativePath.attachment(for: URL(fileURLWithPath: "/w/curso-2/a b.pdf"), in: base) == "@\"/w/curso-2/a b.pdf\"")
    }

    @Test func referencedPathsAreParsedFromPrompt() {
        let prompt = "mira @material/a.pdf y @/Users/x/Desktop/a.png y @\"/Users/y/mi carpeta/b c.pdf\" ok @alguien"
        #expect(ScopeRelativePath.absolutePaths(in: prompt) == ["/Users/x/Desktop/a.png", "/Users/y/mi carpeta/b c.pdf"])
        #expect(ScopeRelativePath.absolutePaths(in: "sin refs") == [])
    }

    @Test func extraDirectoriesAreOutsideCwdAndDeduplicated() {
        let prompt = "@/Users/x/Desktop/a.png @/Users/x/Desktop/b.png @/w/curso/material/c.pdf @/Users/y/d.pdf"
        #expect(ScopeRelativePath.extraDirectories(in: prompt, cwd: base) == ["/Users/x/Desktop", "/Users/y"])
        #expect(ScopeRelativePath.extraDirectories(in: "hola", cwd: base) == [])
    }
}

struct PasteClassifierTests {
    private let file = URL(fileURLWithPath: "/Users/x/a.pdf")

    @Test func fileURLsWinOverEverythingElse() {
        #expect(PasteClassifier.classify(fileURLs: [file], hasImage: true, hasText: true) == .files([file]))
    }

    @Test func imageWithoutTextIsAnImage() {
        #expect(PasteClassifier.classify(fileURLs: [], hasImage: true, hasText: false) == .image)
    }

    @Test func textStaysPlainPaste() {
        #expect(PasteClassifier.classify(fileURLs: [], hasImage: true, hasText: true) == .text)
        #expect(PasteClassifier.classify(fileURLs: [], hasImage: false, hasText: true) == .text)
        #expect(PasteClassifier.classify(fileURLs: [], hasImage: false, hasText: false) == .text)
    }
}
