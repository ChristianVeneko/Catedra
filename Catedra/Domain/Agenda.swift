import Foundation

struct DayGroup: Identifiable, Sendable, Equatable {
    let day: Date
    let activities: [Activity]
    var id: Date { day }
}

/// Dashboard model: what to show in "Hoy", derived purely from activities and the current time.
struct Agenda: Sendable, Equatable {
    var hero: Activity?
    var overdue: [Activity] = []
    var days: [DayGroup] = []
    var later: [Activity] = []
    var undated: [Activity] = []

    static let horizonDays = 14

    static func build(
        activities: [Activity],
        stateOf: (Activity) -> ActivityState,
        now: Date,
        calendar: Calendar
    ) -> Agenda {
        let open = activities.filter { stateOf($0) != .submitted }
        var agenda = Agenda()
        agenda.undated = open.filter { $0.due == nil }.sorted(by: byName)
        let dated = open.compactMap { a in a.due.map { (a, $0) } }
        agenda.overdue = dated.filter { $0.1 < now }.sorted { $0.1 > $1.1 }.map(\.0)
        let upcoming = dated.filter { $0.1 >= now }.sorted { $0.1 < $1.1 }
        agenda.hero = upcoming.first?.0
        let rest = upcoming.dropFirst()
        let horizon = calendar.date(byAdding: .day, value: horizonDays, to: calendar.startOfDay(for: now)) ?? now
        let near = rest.filter { $0.1 < horizon }
        agenda.later = rest.filter { $0.1 >= horizon }.map(\.0)
        let grouped = Dictionary(grouping: near) { calendar.startOfDay(for: $0.1) }
        agenda.days = grouped.keys.sorted().map { day in DayGroup(day: day, activities: grouped[day]!.map(\.0)) }
        return agenda
    }

    private static func byName(_ a: Activity, _ b: Activity) -> Bool {
        (a.courseName, a.name) < (b.courseName, b.name)
    }
}
