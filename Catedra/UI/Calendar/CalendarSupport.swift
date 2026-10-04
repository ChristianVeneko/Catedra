import AppKit
import SwiftUI

extension AppContainer {
    /// Every calendar entry of the current workspace plus the user's study blocks.
    var calendarEntries: [CalendarEntry] {
        planner.entries(activities: workspace.snapshot.activities, events: workspace.snapshot.calendarEvents,
                        courses: workspace.snapshot.courses)
    }

    func color(for entry: CalendarEntry) -> Color {
        CoursePalette.color(for: workspace.snapshot.courses.first { $0.folderName == entry.courseFolder })
    }

    /// Activity -> its detail; class/event -> its URL; study block -> its editor.
    func open(entry: CalendarEntry) {
        switch entry.link {
        case .activity(let id): reveal(activityID: id)
        case .url(let url): NSWorkspace.shared.open(url)
        case .studyBlock(let id): planner.edit(blockID: id)
        case nil: break
        }
    }
}

enum CalendarFormat {
    static func weekday(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(locale: Formatters.locale, calendar: Formatters.calendar, timeZone: Formatters.timeZone)
            .weekday(.abbreviated)).capitalizedFirst
    }

    static func dayNumber(_ date: Date) -> String { "\(Formatters.calendar.component(.day, from: date))" }

    static func period(_ date: Date, mode: CalendarViewMode) -> String {
        let style = Date.FormatStyle(locale: Formatters.locale, calendar: Formatters.calendar, timeZone: Formatters.timeZone)
        switch mode {
        case .month: return date.formatted(style.month(.wide).year()).capitalizedFirst
        case .week: return date.formatted(style.day().month(.wide))
        }
    }

    /// 24-hour clock, "23:59".
    static func clock(_ date: Date) -> String {
        let parts = Formatters.calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    static func timeRange(_ start: Date, _ end: Date?) -> String {
        guard let end, end > start else { return clock(start) }
        return "\(clock(start)) – \(clock(end))"
    }

    /// "5 – 11 oct 2026", "28 sep – 4 oct 2026" or "28 dic 2026 – 3 ene 2027".
    static func weekRange(first: Date, last: Date) -> String {
        rangeText(first: first, last: last).replacingOccurrences(of: ".", with: "")
    }

    private static func rangeText(first: Date, last: Date) -> String {
        let calendar = Formatters.calendar
        let style = Date.FormatStyle(locale: Formatters.locale, calendar: calendar, timeZone: Formatters.timeZone)
        let a = calendar.dateComponents([.year, .month], from: first)
        let b = calendar.dateComponents([.year, .month], from: last)
        if a.year != b.year {
            let full = style.day().month(.abbreviated).year()
            return "\(first.formatted(full)) – \(last.formatted(full))"
        }
        let year = last.formatted(style.year())
        if a.month != b.month {
            let short = style.day().month(.abbreviated)
            return "\(first.formatted(short)) – \(last.formatted(short)) \(year)"
        }
        return "\(first.formatted(style.day())) – \(last.formatted(style.day().month(.abbreviated))) \(year)"
    }

    static func hours(_ value: Double) -> String {
        let minutes = Int((value * 60).rounded())
        let (h, m) = (minutes / 60, minutes % 60)
        if h == 0 { return "\(m) min" }
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }
}

/// Everything the week and month grids need, so they render without the app container (previews, snapshot tests).
struct CalendarViewContext {
    let layout: CalendarLayout
    let anchor: Date
    let selectedDay: Date
    let now: Date
    let entries: [CalendarEntry]
    let color: (CalendarEntry) -> Color
    let select: (Date) -> Void
    let open: (CalendarEntry) -> Void
    let create: (Date) -> Void

    var calendar: Calendar { layout.calendar }

    func isWeekend(_ day: Date) -> Bool { calendar.isDateInWeekend(day) }

    /// A deadline whose time already passed.
    func isPast(_ entry: CalendarEntry) -> Bool { entry.kind.isDeadline && entry.start < now }
}

extension CalendarEntry {
    /// Tooltip / VoiceOver text: kind, title, course and time.
    var detailText: String {
        var parts = ["\(kind.label): \(title)"]
        if !courseName.isEmpty { parts.append(courseName) }
        parts.append(CalendarFormat.timeRange(start, kind.isTimed ? end : nil))
        if isDone { parts.append("hecho") }
        return parts.joined(separator: " · ")
    }
}

/// Compact colored row for deadlines and month cells: course-colored icon, title and optional time.
struct CalendarChip: View {
    let entry: CalendarEntry
    let color: Color
    var dimmed = false
    var showsTime = true
    var compact = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: entry.isDone ? "checkmark.circle.fill" : entry.kind.symbolName)
                .font(.system(size: compact ? 8 : 10, weight: .semibold)).foregroundStyle(color)
            Text(entry.title).lineLimit(1).font(compact ? .caption2 : .caption.weight(.medium))
                .strikethrough(dimmed || entry.isDone)
            if showsTime {
                Spacer(minLength: 2)
                Text(CalendarFormat.clock(entry.start)).font(.system(size: 9).monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 5).padding(.vertical, compact ? 1.5 : 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(dimmed ? 0.07 : 0.16), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay(alignment: .leading) { Capsule().fill(color).frame(width: 2).padding(.vertical, 2) }
        .opacity(dimmed ? 0.6 : 1)
    }
}

/// Popover content listing every entry of a crowded day.
struct CalendarOverflowList: View {
    let day: Date
    let entries: [CalendarEntry]
    let context: CalendarViewContext

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Formatters.dayHeader(day)).font(.headline)
            ForEach(entries) { entry in
                Button { context.open(entry) } label: {
                    HStack(spacing: 6) {
                        CalendarChip(entry: entry, color: context.color(entry), dimmed: context.isPast(entry))
                    }
                }
                .buttonStyle(.plain)
                .help(entry.detailText)
            }
        }
        .padding(12).frame(width: 280)
    }
}

/// "3 entregas" style capsule used in the calendar header.
struct CalendarPill: View {
    let symbol: String
    let text: String
    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(.quaternary.opacity(0.7), in: Capsule())
            .foregroundStyle(.secondary)
    }
}

/// Small colored row used in the day list.
struct CalendarEntryLabel: View {
    let entry: CalendarEntry
    let color: Color
    var compact = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: entry.isDone ? "checkmark.circle.fill" : entry.kind.symbolName)
                .font(.system(size: compact ? 9 : 11)).foregroundStyle(color)
            Text(entry.title).lineLimit(1).font(compact ? .caption2 : .callout)
                .strikethrough(entry.isDone)
        }
    }
}
