import Testing
import Foundation
@testable import Catedra

struct LineDiffTests {
    func kinds(_ lines: [DiffLine]) -> [String] {
        lines.map { ($0.kind == .added ? "+" : $0.kind == .removed ? "-" : " ") + $0.text }
    }

    @Test func identicalTextHasNoChanges() {
        let diff = LineDiff.compare(old: "a\nb\n", new: "a\nb\n")
        #expect(kinds(diff) == [" a", " b"])
        #expect(!diff.hasChanges)
    }

    @Test func addedAndRemovedLines() {
        let diff = LineDiff.compare(old: "a\nb\nc", new: "a\nc\nd")
        #expect(kinds(diff) == [" a", "-b", " c", "+d"])
        #expect(diff.addedCount == 1)
        #expect(diff.removedCount == 1)
    }

    @Test func replacedLineShowsRemovalBeforeAddition() {
        let diff = LineDiff.compare(old: "uno\ndos\ntres", new: "uno\nDOS\ntres")
        #expect(kinds(diff) == [" uno", "-dos", "+DOS", " tres"])
    }

    @Test func emptyOldTextIsAllAdded() {
        #expect(kinds(LineDiff.compare(old: "", new: "a\nb")) == ["+a", "+b"])
        #expect(kinds(LineDiff.compare(old: "a\nb", new: "")) == ["-a", "-b"])
    }

    @Test func lineEndingsAreNormalized() {
        #expect(!LineDiff.compare(old: "a\r\nb\r\n", new: "a\nb").hasChanges)
    }

    @Test func oversizedMiddleFallsBackToRemoveThenAdd() {
        let old = (0..<1200).map { "o\($0)" }, new = (0..<1200).map { "n\($0)" }
        let diff = LineDiff.diff(old, new)
        #expect(diff.removedCount == 1200)
        #expect(diff.addedCount == 1200)
        #expect(diff.first?.kind == .removed)
    }

    @Test func condensedCollapsesLongUnchangedRuns() {
        let old = (1...20).map(String.init).joined(separator: "\n")
        let new = old.replacingOccurrences(of: "10", with: "diez")
        let rows = LineDiff.condensed(LineDiff.compare(old: old, new: new), context: 2)
        #expect(rows.first == .gap(count: 7))
        #expect(rows.last == .gap(count: 8))
        #expect(rows.count == 8)
        let changed = rows.compactMap { row -> DiffLine? in if case .line(let l) = row, l.kind != .unchanged { return l }; return nil }
        #expect(changed.map(\.text) == ["10", "diez"])
    }
}
