import SwiftUI

/// Content column of the calendar destination: entries of the selected day.
struct CalendarDayListView: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        let planner = container.planner
        let layout = planner.layout
        let entries = layout.entriesByDay(container.calendarEntries)[layout.calendar.startOfDay(for: planner.selectedDay)] ?? []
        List {
            Section {
                if entries.isEmpty {
                    Text("Nada programado este día.").foregroundStyle(.secondary)
                }
                ForEach(entries) { entry in
                    Button { container.open(entry: entry) } label: { row(entry) }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if case .studyBlock(let id) = entry.link {
                                Button(entry.isDone ? "Marcar como pendiente" : "Marcar como hecho") { planner.toggleDone(blockID: id) }
                                Button("Eliminar", role: .destructive) { planner.delete(blockID: id) }
                            }
                        }
                }
            } header: {
                HStack {
                    Text(Formatters.dayHeader(planner.selectedDay)).font(.headline)
                    Spacer()
                    Button { planner.beginNew(at: defaultStart(planner)) } label: { Image(systemName: "plus") }
                        .buttonStyle(.borderless).help("Nuevo bloque de estudio este día")
                }
            }
        }
        .navigationTitle("Calendario")
        .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 400)
    }

    private func row(_ entry: CalendarEntry) -> some View {
        let color = container.color(for: entry)
        return HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 4)
            VStack(alignment: .leading, spacing: 2) {
                CalendarEntryLabel(entry: entry, color: color)
                Text(subtitle(entry)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 0)
            if case .studyBlock(let id) = entry.link {
                Button { container.planner.toggleDone(blockID: id) } label: {
                    Image(systemName: entry.isDone ? "checkmark.circle.fill" : "circle")
                }
                .buttonStyle(.borderless).help(entry.isDone ? "Marcar como pendiente" : "Marcar como hecho")
            }
        }
        .contentShape(Rectangle())
    }

    private func subtitle(_ entry: CalendarEntry) -> String {
        var parts = [entry.kind.label]
        if entry.kind.isTimed, let end = entry.end { parts.append("\(Formatters.time(entry.start)) – \(Formatters.time(end))") }
        else { parts.append(Formatters.time(entry.start)) }
        if !entry.courseName.isEmpty { parts.append(entry.courseName) }
        return parts.joined(separator: " · ")
    }

    private func defaultStart(_ planner: CalendarModel) -> Date {
        let calendar = planner.layout.calendar
        let day = calendar.startOfDay(for: planner.selectedDay)
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
    }
}
