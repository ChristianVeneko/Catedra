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
}
