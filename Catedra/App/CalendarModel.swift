import Foundation
import Observation

struct StudyBlockEditor: Identifiable, Equatable {
    var block: StudyBlock
    var isNew: Bool
    var id: UUID { block.id }
}

/// State of the "Calendario" destination: visible period, selected day, study blocks and the Calendar.app export.
@Observable @MainActor
final class CalendarModel {
    var mode: CalendarViewMode = .week
    var anchor: Date
    var selectedDay: Date
    var editor: StudyBlockEditor?
    private(set) var blocks: [StudyBlock] = []
    private(set) var isExporting = false
    private(set) var exportMessage: String?
    private(set) var exportFailed = false

    let layout: CalendarLayout
    private let store: StudyBlockStoring
    private let makeExportStore: @MainActor () -> CalendarEventStoring

    init(store: StudyBlockStoring = JSONStudyBlockStore(), calendar: Calendar = CalendarModel.defaultCalendar,
         now: Date = .now, makeExportStore: @escaping @MainActor () -> CalendarEventStoring = { EventKitCalendarStore() }) {
        self.store = store
        self.layout = CalendarLayout(calendar: calendar)
        self.makeExportStore = makeExportStore
        self.anchor = now
        self.selectedDay = calendar.startOfDay(for: now)
    }

    /// The app's pinned calendar (America/Caracas) with Monday as the first weekday.
    static var defaultCalendar: Calendar {
        var calendar = Formatters.calendar
        calendar.firstWeekday = 2
        return calendar
    }

    func load() { blocks = store.load() }

    func entries(activities: [Activity], events: [CalendarEvent], courses: [Course]) -> [CalendarEntry] {
        CalendarBuilder.build(activities: activities, events: events, studyBlocks: blocks, courses: courses)
    }

    // MARK: - Navigation

    func step(by steps: Int) {
        anchor = layout.moved(anchor, mode: mode, by: steps)
    }

    func goToToday(now: Date = .now) {
        anchor = now
        selectedDay = layout.calendar.startOfDay(for: now)
    }

    func select(day: Date) {
        selectedDay = layout.calendar.startOfDay(for: day)
    }

    // MARK: - Study blocks

    func beginNew(at start: Date, activity: Activity? = nil) {
        let block = StudyBlock(title: activity.map { "Estudiar \($0.name)" } ?? "", start: start,
                               end: start.addingTimeInterval(StudyBlock.defaultDuration), activityID: activity?.id,
                               courseFolder: activity?.courseFolderName)
        editor = StudyBlockEditor(block: block, isNew: true)
    }

    /// Start of the next full hour, used when the block is created without picking a slot.
    func nextHour(after now: Date = .now) -> Date {
        let calendar = layout.calendar
        let hour = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        return calendar.date(byAdding: .hour, value: 1, to: hour) ?? now
    }

    func edit(blockID: UUID) {
        guard let block = blocks.first(where: { $0.id == blockID }) else { return }
        editor = StudyBlockEditor(block: block, isNew: false)
    }

    func save(_ block: StudyBlock) {
        var block = block
        if block.title.trimmingCharacters(in: .whitespaces).isEmpty { block.title = StudyBlock.defaultTitle }
        if block.end <= block.start { block.end = block.start.addingTimeInterval(StudyBlock.defaultDuration) }
        if let index = blocks.firstIndex(where: { $0.id == block.id }) { blocks[index] = block } else { blocks.append(block) }
        persist()
    }

    func delete(blockID: UUID) {
        blocks.removeAll { $0.id == blockID }
        persist()
    }

    func toggleDone(blockID: UUID) {
        guard let index = blocks.firstIndex(where: { $0.id == blockID }) else { return }
        blocks[index].done.toggle()
        persist()
    }

    private func persist() {
        try? store.save(blocks)
    }

    // MARK: - Calendar.app export

    func export(entries: [CalendarEntry], now: Date = .now) async {
        guard !isExporting else { return }
        isExporting = true
        defer { isExporting = false }
        do {
            let result = try await CalendarExportUseCase(store: makeExportStore()).export(entries: entries, now: now)
            exportMessage = result.summary
            exportFailed = false
        } catch {
            exportMessage = (error as? LocalizedError)?.errorDescription ?? "No se pudo exportar a Calendario: \(error.localizedDescription)"
            exportFailed = true
        }
    }

    func dismissExportMessage() { exportMessage = nil }
}
