import SwiftUI

/// Detail column of the calendar destination: week or month grid with its toolbar.
struct CalendarView: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        @Bindable var planner = container.planner
        let entries = container.calendarEntries
        VStack(spacing: 0) {
            header(planner: planner, entries: entries)
            if let message = planner.exportMessage { exportBanner(message, failed: planner.exportFailed) }
            Divider()
            switch planner.mode {
            case .week: CalendarWeekView(entries: entries)
            case .month: CalendarMonthView(entries: entries)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Picker("Vista", selection: $planner.mode) {
                    Text("Semana").tag(CalendarViewMode.week)
                    Text("Mes").tag(CalendarViewMode.month)
                }
                .pickerStyle(.segmented)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button { planner.step(by: -1) } label: { Label("Anterior", systemImage: "chevron.left") }
                Button("Hoy") { planner.goToToday() }
                Button { planner.step(by: 1) } label: { Label("Siguiente", systemImage: "chevron.right") }
                Button { planner.beginNew(at: planner.nextHour()) } label: { Label("Nuevo bloque de estudio", systemImage: "plus") }
                    .help("Nuevo bloque de estudio")
                Menu {
                    Button("Exportar a Calendario") { Task { await planner.export(entries: entries) } }
                        .disabled(planner.isExporting)
                } label: {
                    Label("Calendario", systemImage: "square.and.arrow.up")
                }
                .help("Exportar entregas, clases y bloques a Calendario.app")
            }
        }
        .sheet(item: $planner.editor) { editor in
            StudyBlockSheet(editor: editor).environment(container)
        }
    }

    private func header(planner: CalendarModel, entries: [CalendarEntry]) -> some View {
        let days = planner.layout.weekDays(containing: planner.anchor)
        let load = planner.layout.weeklyLoad(entries: entries, weekContaining: planner.anchor)
        let title = planner.mode == .week
            ? CalendarFormat.weekRange(first: days.first ?? planner.anchor, last: days.last ?? planner.anchor)
            : CalendarFormat.period(planner.anchor, mode: .month)
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.title2.weight(.semibold))
            Spacer()
            if planner.mode == .week {
                CalendarPill(symbol: "flag.fill", text: "\(load.deadlines) \(load.deadlines == 1 ? "entrega" : "entregas")")
                CalendarPill(symbol: "book", text: "\(CalendarFormat.hours(load.studyHours)) de estudio")
                if let first = days.first, let end = planner.layout.calendar.date(byAdding: .day, value: 7, to: first),
                   let focusText = FocusAggregation.weekComparisonText(
                       actualMinutes: container.focus.minutes(in: DateInterval(start: first, end: end)), plannedHours: load.studyHours) {
                    CalendarPill(symbol: "timer", text: focusText)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private func exportBanner(_ message: String, failed: Bool) -> some View {
        HStack {
            Image(systemName: failed ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(failed ? .orange : .green)
            Text(message).font(.callout)
            Spacer()
            Button { container.planner.dismissExportMessage() } label: { Image(systemName: "xmark") }.buttonStyle(.borderless)
        }
        .padding(.horizontal, 16).padding(.vertical, 6)
        .background((failed ? Color.orange : Color.green).opacity(0.12))
    }
}
