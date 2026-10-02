import Foundation

/// Text and urgency shown in the menu bar next to the app glyph.
struct MenuBarLabel: Equatable, Sendable {
    enum Tone: Equatable, Sendable { case normal, warning, critical }

    var text: String?
    var tone: Tone

    static let warningThreshold: TimeInterval = 24 * 3600
    static let criticalThreshold: TimeInterval = 3 * 3600

    static func make(nextDue: Date?, now: Date, showsCountdown: Bool) -> MenuBarLabel {
        guard let due = nextDue, due >= now else { return MenuBarLabel(text: nil, tone: .normal) }
        let remaining = due.timeIntervalSince(now)
        let tone: Tone = remaining < criticalThreshold ? .critical : remaining < warningThreshold ? .warning : .normal
        return MenuBarLabel(text: showsCountdown ? CountdownFormatter.text(until: due, from: now) : nil, tone: tone)
    }
}

/// Open activities with a future due date, nearest first.
enum UpcomingActivities {
    static func next(_ activities: [Activity], stateOf: (Activity) -> ActivityState, now: Date, limit: Int) -> [Activity] {
        let open = activities.compactMap { a -> (Activity, Date)? in
            guard let due = a.due, due >= now, stateOf(a) != .submitted else { return nil }
            return (a, due)
        }
        return open.sorted { ($0.1, $0.0.name) < ($1.1, $1.0.name) }.prefix(limit).map(\.0)
    }
}
