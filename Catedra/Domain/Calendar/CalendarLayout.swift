import Foundation

enum CalendarViewMode: String, Hashable, Sendable { case week, month }

struct WeeklyLoad: Equatable, Sendable {
    let deadlines: Int
    let studyHours: Double
}

/// Day bucketing and week/month geometry for the calendar views. Pure; time zone and first weekday come from `calendar`.
struct CalendarLayout: Sendable {
    let calendar: Calendar

    func weekDays(containing date: Date) -> [Date] {
        let start = weekStart(of: date)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    /// Full weeks (Monday-first by default `firstWeekday`) covering the month of `date`.
    func monthWeeks(containing date: Date) -> [[Date]] {
        guard let month = calendar.dateInterval(of: .month, for: date) else { return [] }
        var weeks: [[Date]] = []
        var cursor = weekStart(of: month.start)
        while cursor < month.end {
            weeks.append(weekDays(containing: cursor))
            guard let next = calendar.date(byAdding: .day, value: 7, to: cursor) else { break }
            cursor = next
        }
        return weeks
    }

    func entriesByDay(_ entries: [CalendarEntry]) -> [Date: [CalendarEntry]] {
        Dictionary(grouping: entries) { calendar.startOfDay(for: $0.start) }
            .mapValues { $0.sorted { ($0.start, $0.title, $0.id) < ($1.start, $1.title, $1.id) } }
    }

    func moved(_ date: Date, mode: CalendarViewMode, by steps: Int) -> Date {
        calendar.date(byAdding: mode == .week ? .day : .month, value: mode == .week ? 7 * steps : steps, to: date) ?? date
    }

    func weeklyLoad(entries: [CalendarEntry], weekContaining date: Date) -> WeeklyLoad {
        let days = weekDays(containing: date)
        guard let first = days.first, let end = calendar.date(byAdding: .day, value: 7, to: first) else {
            return WeeklyLoad(deadlines: 0, studyHours: 0)
        }
        let inWeek = entries.filter { $0.start >= first && $0.start < end }
        let seconds = inWeek.filter { $0.kind == .estudio }.reduce(0) { $0 + $1.duration }
        return WeeklyLoad(deadlines: inWeek.filter { $0.kind.isDeadline }.count, studyHours: seconds / 3600)
    }

    /// Hours shown in the week grid: 07:00-23:00 widened to fit every timed entry (end exclusive, within 0..<24).
    func visibleHours(for timed: [CalendarEntry]) -> Range<Int> {
        var first = 7, last = 23
        for entry in timed {
            let day = calendar.startOfDay(for: entry.start)
            let startHour = calendar.component(.hour, from: entry.start)
            let end = entry.end.flatMap { $0 > entry.start ? $0 : nil } ?? entry.start.addingTimeInterval(CalendarLanes.defaultDuration)
            let endHours = Int((end.timeIntervalSince(day) / 3600).rounded(.up))
            first = min(first, startHour)
            last = max(last, min(24, endHours))
        }
        return first..<last
    }

    private func weekStart(of date: Date) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }
}
