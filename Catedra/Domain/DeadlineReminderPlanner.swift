import Foundation

/// A local notification to schedule for one activity and one lead time.
struct DeadlineReminder: Identifiable, Equatable, Sendable {
    let id: String
    let activityID: Activity.ID
    let offsetHours: Int
    let fireDate: Date
    let title: String
    let body: String
}

/// Which reminders the user wants: enabled flag, the three standard lead times and one optional custom one.
struct ReminderPreferences: Equatable, Sendable {
    var enabled = false
    var at48h = true
    var at24h = true
    var at3h = true
    var customEnabled = false
    var customHours = 12

    /// Active lead times in hours, longest first. Empty when reminders are off.
    var offsetsHours: [Int] {
        guard enabled else { return [] }
        var result: [Int] = []
        if at48h { result.append(48) }
        if at24h { result.append(24) }
        if customEnabled, customHours > 0 { result.append(customHours) }
        if at3h { result.append(3) }
        var seen = Set<Int>()
        return result.filter { seen.insert($0).inserted }.sorted(by: >)
    }
}

/// Pure planning of deadline reminders. Re-planning is idempotent: ids depend only on activity, lead time and due date.
enum DeadlineReminderPlanner {
    static let idPrefix = "catedra.deadline."
    static let defaultOffsetsHours = [48, 24, 3]
    /// macOS (like iOS) keeps a bounded number of pending local notifications; the nearest ones win.
    static let maxPending = 60

    static func plan(
        activities: [Activity],
        stateOf: (Activity) -> ActivityState,
        now: Date,
        offsetsHours: [Int] = defaultOffsetsHours,
        limit: Int = maxPending,
        formatDue: (Date) -> String = Formatters.due
    ) -> [DeadlineReminder] {
        var seen = Set<Int>()
        let offsets = offsetsHours.filter { $0 > 0 && seen.insert($0).inserted }
        var reminders: [DeadlineReminder] = []
        for activity in activities {
            guard let due = activity.due, stateOf(activity) != .submitted else { continue }
            for hours in offsets {
                let fire = due.addingTimeInterval(-Double(hours) * 3600)
                guard fire > now else { continue }
                reminders.append(DeadlineReminder(
                    id: "\(idPrefix)\(activity.id)|\(hours)|\(Int(due.timeIntervalSince1970))",
                    activityID: activity.id, offsetHours: hours, fireDate: fire,
                    title: "Vence en \(hours) h: \(activity.name)",
                    body: "\(activity.courseName) · \(activity.kind.displayName) · \(formatDue(due))"))
            }
        }
        reminders.sort { ($0.fireDate, $0.id) < ($1.fireDate, $1.id) }
        return Array(reminders.prefix(max(0, limit)))
    }

    struct Diff: Equatable, Sendable {
        var toAdd: [DeadlineReminder]
        var toRemove: [String]
    }

    /// What to change so the pending requests match `planned`. Only ids with our prefix are ever removed.
    static func diff(planned: [DeadlineReminder], pendingIDs: Set<String>) -> Diff {
        let plannedIDs = Set(planned.map(\.id))
        return Diff(
            toAdd: planned.filter { !pendingIDs.contains($0.id) },
            toRemove: pendingIDs.filter { $0.hasPrefix(idPrefix) && !plannedIDs.contains($0) }.sorted())
    }
}
