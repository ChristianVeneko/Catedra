import SwiftUI

/// Month destination bound to the app container.
struct CalendarMonthView: View {
    @Environment(AppContainer.self) private var container
    let entries: [CalendarEntry]

    var body: some View {
        let planner = container.planner
        MonthGridView(context: CalendarViewContext(
            layout: planner.layout, anchor: planner.anchor, selectedDay: planner.selectedDay, now: container.clock.now,
            entries: entries, color: { container.color(for: $0) },
            select: { planner.select(day: $0) }, open: { container.open(entry: $0) },
            create: { start in planner.beginNew(at: start) }))
    }
}

/// Month grid: weekday header and one cell per day with up to three chips. Pure of the container.
struct MonthGridView: View {
    let context: CalendarViewContext

    var body: some View {
        let weeks = context.layout.monthWeeks(containing: context.anchor)
        let byDay = context.layout.entriesByDay(context.entries)
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(weeks.first ?? [], id: \.self) { day in
                    Text(CalendarFormat.weekday(day).uppercased()).font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary).opacity(context.isWeekend(day) ? 0.65 : 1)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 6)
            VStack(spacing: 0) {
                ForEach(weeks, id: \.first) { week in
                    HStack(spacing: 0) {
                        ForEach(week, id: \.self) { day in MonthCell(day: day, entries: byDay[day] ?? [], context: context) }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
            .padding(.horizontal, 12).padding(.bottom, 12)
        }
    }
}

private struct MonthCell: View {
    let day: Date
    let entries: [CalendarEntry]
    let context: CalendarViewContext
    @State private var showsAll = false

    private let maxChips = 3

    var body: some View {
        let calendar = context.calendar
        let inMonth = calendar.isDate(day, equalTo: context.anchor, toGranularity: .month)
        let isToday = calendar.isDate(day, inSameDayAs: context.now)
        let isSelected = calendar.isDate(day, inSameDayAs: context.selectedDay)
        let visible = Array(entries.prefix(maxChips))
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(CalendarFormat.dayNumber(day)).font(.caption.weight(isToday ? .bold : .semibold))
                    .foregroundStyle(isToday ? Color.white : (inMonth ? Color.primary : Color.secondary))
                    .frame(minWidth: 22, minHeight: 22)
                    .background(isToday ? Color.accentColor : .clear, in: Circle())
                Spacer(minLength: 0)
                if entries.count > maxChips { dots }
            }
            ForEach(visible) { entry in
                let color = context.color(entry)
                Button { context.open(entry) } label: {
                    CalendarChip(entry: entry, color: color, dimmed: context.isPast(entry), showsTime: false, compact: true)
                }
                .buttonStyle(.plain)
                .help(entry.detailText).accessibilityLabel(entry.detailText)
            }
            if entries.count > maxChips {
                Button { showsAll = true } label: {
                    Text("+\(entries.count - maxChips) más").font(.caption2.weight(.semibold)).foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 5)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showsAll) { CalendarOverflowList(day: day, entries: entries, context: context) }
            }
            Spacer(minLength: 0)
        }
        .padding(4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(background(inMonth: inMonth, isToday: isToday))
        .overlay(Rectangle().strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
        .overlay { if isSelected { RoundedRectangle(cornerRadius: 4).strokeBorder(Color.accentColor, lineWidth: 2).padding(1) } }
        .opacity(inMonth ? 1 : 0.5)
        .contentShape(Rectangle())
        .onTapGesture { context.select(day) }
        .onTapGesture(count: 2) { context.create(context.calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Formatters.dayHeader(day) + (entries.isEmpty ? "" : ", \(entries.count) elementos"))
    }

    /// Course-colored dots summarising crowded days.
    private var dots: some View {
        HStack(spacing: 2) {
            ForEach(uniqueColors.prefix(4), id: \.self) { index in
                Circle().fill(index.color).frame(width: 5, height: 5)
            }
        }
    }

    private struct DotColor: Hashable { let key: String; let color: Color }

    private var uniqueColors: [DotColor] {
        var seen = Set<String>()
        return entries.compactMap { entry in
            let color = context.color(entry)
            return seen.insert(entry.courseFolder ?? "-").inserted ? DotColor(key: entry.courseFolder ?? "-", color: color) : nil
        }
    }

    private func background(inMonth: Bool, isToday: Bool) -> Color {
        if isToday { return Color.accentColor.opacity(0.07) }
        if !inMonth { return Color.primary.opacity(0.04) }
        return context.isWeekend(day) ? Color.primary.opacity(0.025) : .clear
    }
}
