import Foundation

struct Change<Value: Sendable & Equatable>: Sendable, Equatable {
    let activity: Activity
    let oldValue: Value
    let newValue: Value
}

/// Difference between two activity snapshots, used for the post-sync summary.
struct ActivityDiff: Sendable, Equatable {
    var added: [Activity] = []
    var removed: [Activity] = []
    var dueChanges: [Change<Date?>] = []
    var statusChanges: [Change<String>] = []
    /// Grades or teacher feedback that appeared or changed (from the grade reports and the activities).
    var gradeChanges: [GradeChange] = []

    var isEmpty: Bool { added.isEmpty && removed.isEmpty && dueChanges.isEmpty && statusChanges.isEmpty && gradeChanges.isEmpty }

    static func compare(before: [Activity], after: [Activity]) -> ActivityDiff {
        func key(_ a: Activity) -> String { a.url?.absoluteString ?? a.folder }
        let old = Dictionary(before.map { (key($0), $0) }, uniquingKeysWith: { first, _ in first })
        let new = Dictionary(after.map { (key($0), $0) }, uniquingKeysWith: { first, _ in first })
        var diff = ActivityDiff()
        diff.added = after.filter { old[key($0)] == nil }
        diff.removed = before.filter { new[key($0)] == nil }
        for a in after {
            guard let o = old[key(a)] else { continue }
            if o.due != a.due { diff.dueChanges.append(Change(activity: a, oldValue: o.due, newValue: a.due)) }
            if o.rawStatus != a.rawStatus { diff.statusChanges.append(Change(activity: a, oldValue: o.rawStatus, newValue: a.rawStatus)) }
        }
        return diff
    }
}
