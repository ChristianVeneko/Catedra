import SwiftUI

/// Week destination bound to the app container.
struct CalendarWeekView: View {
    @Environment(AppContainer.self) private var container
    let entries: [CalendarEntry]

    var body: some View {
        let planner = container.planner
        WeekGridView(context: CalendarViewContext(
            layout: planner.layout, anchor: planner.anchor, selectedDay: planner.selectedDay, now: container.clock.now,
            entries: entries, color: { container.color(for: $0) },
            select: { planner.select(day: $0) }, open: { container.open(entry: $0) },
            create: { start in planner.beginNew(at: start) }))
    }
}

/// Week grid: day headers, a deadline strip and the hours grid. Pure of the container.
struct WeekGridView: View {
    let context: CalendarViewContext
    /// `false` renders the whole grid unscrolled (snapshots: `ImageRenderer` does not draw `ScrollView` content).
    var scrolls = true

    static let hourHeight: CGFloat = 52
    static let gutter: CGFloat = 52

    var body: some View {
        let days = context.layout.weekDays(containing: context.anchor)
        let byDay = context.layout.entriesByDay(context.entries)
        let weekEntries = days.flatMap { byDay[$0] ?? [] }
        let hours = context.layout.visibleHours(for: weekEntries.filter(\.kind.isTimed))
        VStack(spacing: 0) {
            headerRow(days)
            deadlineStrip(days, byDay: byDay)
            Divider()
            grid(days, byDay: byDay, hours: hours, isEmpty: weekEntries.isEmpty)
        }
    }

    // MARK: - Header

    private func headerRow(_ days: [Date]) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: Self.gutter)
            ForEach(days, id: \.self) { day in
                let isToday = context.calendar.isDate(day, inSameDayAs: context.now)
                let isSelected = context.calendar.isDate(day, inSameDayAs: context.selectedDay)
                Button { context.select(day) } label: {
                    VStack(spacing: 3) {
                        Text(CalendarFormat.weekday(day).uppercased()).font(.caption2.weight(.semibold))
                            .foregroundStyle(isToday ? Color.accentColor : .secondary)
                        Text(CalendarFormat.dayNumber(day)).font(.title3.weight(isToday ? .bold : .medium))
                            .foregroundStyle(isToday ? Color.white : .primary)
                            .frame(width: 32, height: 32)
                            .background(isToday ? Color.accentColor : (isSelected ? Color.accentColor.opacity(0.14) : .clear), in: Circle())
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
                    .opacity(context.isWeekend(day) && !isToday ? 0.6 : 1)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Formatters.dayHeader(day) + (isToday ? ", hoy" : ""))
            }
        }
    }

    // MARK: - Deadline strip

    private func deadlineStrip(_ days: [Date], byDay: [Date: [CalendarEntry]]) -> some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 2) {
                Image(systemName: "flag.fill").font(.caption2)
                Text("Entregas").font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(.secondary).frame(width: Self.gutter).padding(.top, 8)
            ForEach(days, id: \.self) { day in
                DeadlineCell(day: day, entries: (byDay[day] ?? []).filter { !$0.kind.isTimed }, context: context)
            }
        }
        .frame(minHeight: 46)
        .background(Color.primary.opacity(0.035))
    }

    // MARK: - Hours grid

    private func grid(_ days: [Date], byDay: [Date: [CalendarEntry]], hours: Range<Int>, isEmpty: Bool) -> some View {
        let content = HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 0) {
                ForEach(Array(hours), id: \.self) { hour in
                    Text(String(format: "%02d:00", hour)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        .frame(height: Self.hourHeight, alignment: .top).offset(y: -6).id(hour)
                }
            }
            .frame(width: Self.gutter)
            ForEach(days, id: \.self) { day in
                DayColumn(day: day, entries: (byDay[day] ?? []).filter(\.kind.isTimed), hours: hours, context: context)
            }
        }
        .padding(.top, 8)
        return Group {
            if scrolls {
                ScrollViewReader { proxy in
                    ScrollView { content }
                        .onAppear { proxy.scrollTo(scrollTarget(days, byDay: byDay, hours: hours), anchor: .top) }
                }
            } else {
                content
            }
        }
        .overlay { if isEmpty { emptyState } }
    }

    /// Hour to bring into view: an hour before now (current week), else before the first timed entry, else the range start.
    private func scrollTarget(_ days: [Date], byDay: [Date: [CalendarEntry]], hours: Range<Int>) -> Int {
        let calendar = context.calendar
        var target = hours.lowerBound
        if days.contains(where: { calendar.isDate($0, inSameDayAs: context.now) }) {
            target = calendar.component(.hour, from: context.now) - 1
        } else if let first = days.flatMap({ byDay[$0] ?? [] }).filter(\.kind.isTimed).map(\.start).min() {
            target = calendar.component(.hour, from: first) - 1
        }
        return min(max(target, hours.lowerBound), hours.upperBound - 1)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "calendar.badge.checkmark").font(.system(size: 30)).foregroundStyle(.secondary)
            Text("Semana libre").font(.headline)
            Text("No hay entregas, clases ni bloques de estudio. Haga clic en una hora para planificar estudio.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 280)
        }
        .padding(20).card().allowsHitTesting(false)
    }
}

private struct DeadlineCell: View {
    let day: Date
    let entries: [CalendarEntry]
    let context: CalendarViewContext
    @State private var showsAll = false

    private let maxChips = 2

    var body: some View {
        let visible = entries.count > maxChips ? Array(entries.prefix(maxChips - 1)) : entries
        let hidden = entries.count - visible.count
        VStack(alignment: .leading, spacing: 3) {
            ForEach(visible) { entry in
                Button { context.open(entry) } label: { chip(entry) }
                    .buttonStyle(.plain)
                    .help(entry.detailText).accessibilityLabel(entry.detailText)
            }
            if hidden > 0 {
                Button { showsAll = true } label: {
                    Text("+\(hidden) más").font(.caption2.weight(.semibold)).foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 5)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showsAll) { CalendarOverflowList(day: day, entries: entries, context: context) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(3)
        .background(context.calendar.isDate(day, inSameDayAs: context.now) ? Color.accentColor.opacity(0.06) : .clear)
        .overlay(alignment: .leading) { Divider() }
    }

    private func chip(_ entry: CalendarEntry) -> some View {
        let color = context.color(entry)
        let past = context.isPast(entry)
        return VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .top, spacing: 3) {
                Image(systemName: entry.kind.symbolName).font(.system(size: 8, weight: .bold)).foregroundStyle(color).padding(.top, 2)
                Text(entry.title).font(.caption2.weight(.medium)).lineLimit(2).strikethrough(past)
                    .multilineTextAlignment(.leading)
            }
            Text(CalendarFormat.clock(entry.start)).font(.system(size: 9).monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 5).padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(past ? 0.07 : 0.17), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay(alignment: .leading) { Capsule().fill(color).frame(width: 2.5).padding(.vertical, 2) }
        .opacity(past ? 0.6 : 1)
    }
}

private struct DayColumn: View {
    let day: Date
    let entries: [CalendarEntry]
    let hours: Range<Int>
    let context: CalendarViewContext

    private var hourHeight: CGFloat { WeekGridView.hourHeight }

    var body: some View {
        let calendar = context.calendar
        let isToday = calendar.isDate(day, inSameDayAs: context.now)
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                background(isToday: isToday)
                Color.clear.contentShape(Rectangle())
                    .gesture(SpatialTapGesture().onEnded { tap in
                        let hour = min(23, max(0, hours.lowerBound + Int(tap.location.y / hourHeight)))
                        let start = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
                        context.select(day)
                        context.create(start)
                    })
                ForEach(CalendarLanes.assign(entries), id: \.entry.id) { laned in
                    let width = geo.size.width / CGFloat(laned.laneCount)
                    TimedBlock(entry: laned.entry, color: context.color(laned.entry), height: height(laned.entry),
                               onOpen: { context.open(laned.entry) })
                        .frame(width: max(width - 3, 8), height: height(laned.entry))
                        .offset(x: CGFloat(laned.lane) * width + 1, y: y(laned.entry))
                }
                if isToday { nowLine }
            }
        }
        .frame(maxWidth: .infinity).frame(height: CGFloat(hours.count) * hourHeight)
        .overlay(alignment: .leading) { Divider() }
    }

    private func background(isToday: Bool) -> some View {
        ZStack(alignment: .top) {
            if isToday { Color.accentColor.opacity(0.05) } else if context.isWeekend(day) { Color.primary.opacity(0.03) }
            VStack(spacing: 0) {
                ForEach(Array(hours), id: \.self) { _ in
                    Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1).frame(height: hourHeight, alignment: .top)
                }
            }
        }
    }

    private var nowLine: some View {
        let parts = context.calendar.dateComponents([.hour, .minute], from: context.now)
        let hour = Double(parts.hour ?? 0) + Double(parts.minute ?? 0) / 60
        let offset = (hour - Double(hours.lowerBound)) * Double(hourHeight)
        return Group {
            if offset >= 0 && offset <= Double(hours.count) * Double(hourHeight) {
                HStack(spacing: 0) {
                    Circle().fill(Color.red).frame(width: 8, height: 8).offset(x: -4)
                    Rectangle().fill(Color.red).frame(height: 1.5)
                }
                .offset(y: CGFloat(offset) - 4)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }

    private func y(_ entry: CalendarEntry) -> CGFloat {
        let parts = context.calendar.dateComponents([.hour, .minute], from: entry.start)
        let hour = Double(parts.hour ?? 0) + Double(parts.minute ?? 0) / 60
        return CGFloat(hour - Double(hours.lowerBound)) * hourHeight
    }

    private func height(_ entry: CalendarEntry) -> CGFloat {
        let seconds = entry.duration > 0 ? entry.duration : CalendarLanes.defaultDuration
        return max(CGFloat(seconds / 3600) * hourHeight - 2, 22)
    }
}

private struct TimedBlock: View {
    let entry: CalendarEntry
    let color: Color
    let height: CGFloat
    let onOpen: () -> Void

    private var isStudy: Bool { entry.kind == .estudio }

    var body: some View {
        Button(action: onOpen) {
            Group {
                if height < 38 {
                    HStack(spacing: 4) {
                        icon
                        Text(entry.title).font(.caption2.weight(.semibold)).lineLimit(1)
                        Text(CalendarFormat.clock(entry.start)).font(.system(size: 9).monospacedDigit()).foregroundStyle(.secondary)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 3) {
                            icon
                            Text(entry.title).font(.caption.weight(.semibold)).lineLimit(height < 60 ? 1 : 2)
                                .strikethrough(entry.isDone)
                        }
                        Text(CalendarFormat.timeRange(entry.start, entry.end)).font(.system(size: 10).monospacedDigit())
                            .foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            .padding(.leading, 8).padding(.trailing, 4).padding(.vertical, 3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(color.opacity(entry.isDone ? 0.07 : (isStudy ? 0.10 : 0.20)), in: shape)
            .overlay(alignment: .leading) { Capsule().fill(color).frame(width: 3).padding(.vertical, 3).padding(.leading, 2) }
            .overlay { border }
            .opacity(entry.isDone ? 0.6 : 1)
            .clipShape(shape)
        }
        .buttonStyle(.plain)
        .help(entry.detailText)
        .accessibilityLabel(entry.detailText)
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 6, style: .continuous) }

    @ViewBuilder
    private var border: some View {
        if isStudy {
            shape.strokeBorder(color.opacity(0.75), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        } else {
            shape.strokeBorder(color.opacity(0.25), lineWidth: 0.5)
        }
    }

    private var icon: some View {
        Image(systemName: entry.isDone ? "checkmark.circle.fill" : entry.kind.symbolName)
            .font(.system(size: 9, weight: .semibold)).foregroundStyle(color)
    }
}
