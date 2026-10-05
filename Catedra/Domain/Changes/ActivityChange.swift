import Foundation

/// What is kept about an activity between syncs to notice edits. Dates and the normalized `enunciado.md` text.
struct ActivitySnapshot: Codable, Equatable, Sendable {
    var text: String?
    var due: Date?
    var opens: Date?
    var cutoff: Date?
}

struct DateChange: Codable, Equatable, Sendable {
    enum Field: String, Codable, Sendable { case due, opens, cutoff

        var label: String {
            switch self {
            case .due: "Entrega"
            case .opens: "Apertura"
            case .cutoff: "Cierre"
            }
        }
    }
    let field: Field
    let old: Date?
    let new: Date?
}

/// An edit of the statement or of the dates of one activity, kept until the user marks it as seen.
struct ActivityChange: Codable, Equatable, Sendable, Identifiable {
    let activityID: String
    var activityName: String
    var courseName: String
    var detectedAt: Date
    /// Snapshot before the first unseen edit and the current one.
    var before: ActivitySnapshot
    var after: ActivitySnapshot
    var seen: Bool

    var id: String { activityID }

    var textChanged: Bool {
        guard let old = before.text, let new = after.text else { return false }
        return old != new
    }

    var dateChanges: [DateChange] {
        var result: [DateChange] = []
        if before.due != after.due { result.append(DateChange(field: .due, old: before.due, new: after.due)) }
        if before.opens != after.opens { result.append(DateChange(field: .opens, old: before.opens, new: after.opens)) }
        if before.cutoff != after.cutoff { result.append(DateChange(field: .cutoff, old: before.cutoff, new: after.cutoff)) }
        return result
    }

    var datesChanged: Bool { !dateChanges.isEmpty }

    var diff: [DiffLine] {
        guard textChanged, let old = before.text, let new = after.text else { return [] }
        return LineDiff.compare(old: old, new: new)
    }
}

/// Persisted tracking state; `nil` on disk means "no baseline yet".
struct ChangeTrackingState: Codable, Equatable, Sendable {
    var snapshots: [String: ActivitySnapshot] = [:]
    var changes: [ActivityChange] = []
}

struct TrackedActivity: Equatable, Sendable {
    let id: String
    let name: String
    let courseName: String
    let snapshot: ActivitySnapshot
}

enum StatementNormalizer {
    /// Metadata lines that change on their own (status, attempts) or are tracked as dates are left out of the text.
    private static let ignoredPrefixes = ["- Estado:", "- Intentos realizados:", "- Apertura:", "- Entrega:", "- Fecha limite",
                                          "- Fecha límite", "- Abre:", "- Cierra:"]

    static func normalize(_ text: String) -> String {
        LineDiff.lines(of: text)
            .filter { line in !ignoredPrefixes.contains { line.hasPrefix($0) } }
            .map { $0.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum ChangeDetector {
    struct Result: Equatable, Sendable {
        var state: ChangeTrackingState
        /// Changes recorded (or refreshed) by this run, to notify about.
        var recorded: [ActivityChange]
        var isBaseline: Bool
    }

    static let seenRetention: TimeInterval = 30 * 24 * 3600

    /// Compares `current` with the stored snapshots. Without a previous state this only takes the baseline.
    static func process(state: ChangeTrackingState?, current: [TrackedActivity], now: Date) -> Result {
        func snapshots(merging previous: [String: ActivitySnapshot]) -> [String: ActivitySnapshot] {
            var result: [String: ActivitySnapshot] = [:]
            for item in current {
                var snapshot = item.snapshot
                if snapshot.text == nil { snapshot.text = previous[item.id]?.text }
                result[item.id] = snapshot
            }
            return result
        }
        guard var state else {
            return Result(state: ChangeTrackingState(snapshots: snapshots(merging: [:]), changes: []), recorded: [], isBaseline: true)
        }
        // A failed or empty read must not wipe what is tracked.
        guard !current.isEmpty else { return Result(state: state, recorded: [], isBaseline: false) }

        var recorded: [ActivityChange] = []
        let merged = snapshots(merging: state.snapshots)
        for item in current {
            guard let previous = state.snapshots[item.id], let updated = merged[item.id], previous != updated else { continue }
            let existing = state.changes.first { $0.activityID == item.id && !$0.seen }
            let base = existing?.before ?? previous
            state.changes.removeAll { $0.activityID == item.id && !$0.seen }
            let change = ActivityChange(activityID: item.id, activityName: item.name, courseName: item.courseName,
                                        detectedAt: now, before: base, after: updated, seen: false)
            if !change.textChanged && !change.datesChanged { continue } // edited back to what the user last saw
            state.changes.append(change)
            recorded.append(change)
        }
        let ids = Set(current.map(\.id))
        state.changes.removeAll { !ids.contains($0.activityID) || ($0.seen && now.timeIntervalSince($0.detectedAt) > seenRetention) }
        state.snapshots = merged
        return Result(state: state, recorded: recorded, isBaseline: false)
    }

    static func markSeen(_ activityID: String, in state: ChangeTrackingState) -> ChangeTrackingState {
        var state = state
        for i in state.changes.indices where state.changes[i].activityID == activityID { state.changes[i].seen = true }
        return state
    }
}

/// Wording of the "enunciado o fecha cambiaron" system notification.
enum ActivityChangeNotification {
    static func content(for changes: [ActivityChange]) -> (title: String, body: String)? {
        guard let first = changes.first else { return nil }
        guard changes.count == 1 else {
            return ("Cátedra: cambios en actividades", "\(changes.count) actividades cambiaron: "
                    + changes.prefix(3).map(\.activityName).joined(separator: ", ") + (changes.count > 3 ? "…" : ""))
        }
        let what: String
        switch (first.textChanged, first.datesChanged) {
        case (true, true): what = "Cambió el enunciado y la fecha"
        case (_, true): what = "Cambió la fecha"
        default: what = "Cambió el enunciado"
        }
        return ("Cátedra: \(what.lowercased())", "\(first.courseName) · \(first.activityName)")
    }

    static func badges(for change: ActivityChange) -> [String] {
        (change.textChanged ? ["Cambió el enunciado"] : []) + (change.datesChanged ? ["Cambió la fecha"] : [])
    }
}
