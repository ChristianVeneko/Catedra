import Testing
import Foundation
@testable import Catedra

struct ActivityDiffTests {
    @Test func detectsAddedAndRemoved() {
        let a = makeActivity(name: "A", url: "u/a", folder: "f/a")
        let b = makeActivity(name: "B", url: "u/b", folder: "f/b")
        let c = makeActivity(name: "C", url: "u/c", folder: "f/c")
        let diff = ActivityDiff.compare(before: [a, b], after: [b, c])
        #expect(diff.added.map(\.name) == ["C"])
        #expect(diff.removed.map(\.name) == ["A"])
        #expect(diff.dueChanges.isEmpty)
        #expect(diff.statusChanges.isEmpty)
    }

    @Test func detectsDueAndStatusChanges() {
        let before = makeActivity(name: "A", due: Date(timeIntervalSince1970: 100), status: "Pendiente", url: "u/a", folder: "f/a")
        let after = makeActivity(name: "A", due: Date(timeIntervalSince1970: 200), status: "Entregado", url: "u/a", folder: "f/a")
        let diff = ActivityDiff.compare(before: [before], after: [after])
        #expect(diff.dueChanges.count == 1)
        #expect(diff.dueChanges.first?.oldValue == Date(timeIntervalSince1970: 100))
        #expect(diff.dueChanges.first?.newValue == Date(timeIntervalSince1970: 200))
        #expect(diff.statusChanges.first?.oldValue == "Pendiente")
        #expect(diff.statusChanges.first?.newValue == "Entregado")
        #expect(!diff.isEmpty)
    }

    @Test func identicalSnapshotsAreEmpty() {
        let a = makeActivity()
        #expect(ActivityDiff.compare(before: [a], after: [a]).isEmpty)
    }
}
