import Testing
import Foundation
@testable import Catedra

@MainActor
final class FakeCalendarStore: CalendarEventStoring {
    var granted = true
    var existing: [ExistingCalendarEvent] = []
    var created: [ExportEvent] = []
    var updated: [(String, ExportEvent)] = []
    var deleted: [String] = []
    var accessRequests = 0
    var window: (Date, Date)?

    func requestAccess() async throws -> Bool { accessRequests += 1; return granted }
    func calendarIdentifier(named: String) throws -> String { "cal-1" }
    func events(calendarID: String, from: Date, to: Date) throws -> [ExistingCalendarEvent] { window = (from, to); return existing }
    func create(_ event: ExportEvent, calendarID: String) throws {
        created.append(event)
        existing.append(ExistingCalendarEvent(identifier: "new-\(created.count)", entryID: event.entryID, title: event.title,
                                              start: event.start, end: event.end, url: event.url,
                                              notes: CalendarMarker.notes(event.notes, entryID: event.entryID)))
    }
    func update(identifier: String, with event: ExportEvent) throws { updated.append((identifier, event)) }
    func delete(identifier: String) throws { deleted.append(identifier); existing.removeAll { $0.identifier == identifier } }
}

struct CalendarExportTests {
    typealias F = CalendarFixtures
    static let now = F.date(5, 12)

    func event(_ id: String, title: String = "T", start: Date = F.date(7, 10)) -> ExportEvent {
        ExportEvent(entryID: id, title: title, start: start, end: start.addingTimeInterval(1800), url: nil, notes: "Control")
    }

    func existing(_ e: ExportEvent, identifier: String) -> ExistingCalendarEvent {
        ExistingCalendarEvent(identifier: identifier, entryID: e.entryID, title: e.title, start: e.start, end: e.end, url: e.url,
                              notes: CalendarMarker.notes(e.notes, entryID: e.entryID))
    }

    @Test func markerRoundTrip() {
        let notes = CalendarMarker.notes("Hola", entryID: "activity:a/b:due")
        #expect(CalendarMarker.entryID(in: notes) == "activity:a/b:due")
        #expect(CalendarMarker.entryID(in: "sin marca") == nil)
        #expect(CalendarMarker.entryID(in: nil) == nil)
    }

    @Test func plansCreateUpdateDeleteAndUnchanged() {
        let keep = event("keep"), changed = event("chg", title: "nuevo"), fresh = event("new")
        let existingEvents = [existing(keep, identifier: "1"), existing(event("chg", title: "viejo"), identifier: "2"),
                              existing(event("gone"), identifier: "3"),
                              ExistingCalendarEvent(identifier: "4", entryID: nil, title: "manual", start: F.date(7, 9),
                                                    end: F.date(7, 10), url: nil, notes: "")]
        let plan = CalendarExportPlanner.plan(desired: [keep, changed, fresh], existing: existingEvents)
        #expect(plan.create == [fresh])
        #expect(plan.update == [ExportUpdate(identifier: "2", event: changed)])
        #expect(plan.delete == ["3"])
        #expect(plan.unchanged == 1)
    }

    @Test func duplicatesOfSameEntryAreRemoved() {
        let e = event("a")
        let plan = CalendarExportPlanner.plan(desired: [e], existing: [existing(e, identifier: "1"), existing(e, identifier: "2")])
        #expect(plan.create.isEmpty && plan.update.isEmpty)
        #expect(plan.delete == ["2"])
    }

    @Test func exportsDeadlinesClassesAndStudyOnly() {
        let a = F.activity("T1", due: F.date(7, 23, 59), opens: F.date(6, 8), cmid: 1)
        let cls = F.event(1, type: "meeting_start", module: "bigbluebuttonbn", start: F.date(8, 18), duration: 3600)
        let other = F.event(2, type: "course", module: "", start: F.date(8, 9))
        let block = StudyBlock(title: "Repaso", start: F.date(9, 9), end: F.date(9, 10))
        let entries = CalendarBuilder.build(activities: [a], events: [cls, other], studyBlocks: [block], courses: F.courses)
        let out = CalendarExportPlanner.events(from: entries, window: F.date(1)..<F.date(30))
        #expect(out.map(\.title) == ["Entrega: T1", "Clase: Evento 1", "Estudio: Repaso"])
        #expect(out[0].end == F.date(7, 23, 59) && out[0].start == F.date(7, 23, 29))
        #expect(out.allSatisfy { !$0.entryID.isEmpty })
        #expect(CalendarExportPlanner.events(from: entries, window: F.date(20)..<F.date(30)).isEmpty)
    }

    @MainActor @Test func useCaseIsIdempotent() async throws {
        let store = FakeCalendarStore()
        let a = F.activity("T1", due: F.date(7, 23, 59))
        let entries = CalendarBuilder.build(activities: [a], events: [], studyBlocks: [], courses: F.courses)
        let useCase = CalendarExportUseCase(store: store)
        let first = try await useCase.export(entries: entries, now: Self.now)
        #expect(first.created == 1 && store.created.count == 1)
        let second = try await useCase.export(entries: entries, now: Self.now)
        #expect(second.created == 0 && second.updated == 0 && second.deleted == 0 && second.unchanged == 1)
        #expect(store.created.count == 1)
    }

    @MainActor @Test func deniedAccessThrowsSpanishError() async {
        let store = FakeCalendarStore()
        store.granted = false
        await #expect(throws: CalendarExportError.accessDenied) {
            try await CalendarExportUseCase(store: store).export(entries: [], now: Self.now)
        }
        #expect(CalendarExportError.accessDenied.errorDescription?.contains("Calendario") == true)
        #expect(store.created.isEmpty)
    }

    @MainActor @Test func removedEntryIsDeletedFromCalendar() async throws {
        let store = FakeCalendarStore()
        store.existing = [existing(event("old"), identifier: "9")]
        let result = try await CalendarExportUseCase(store: store).export(entries: [], now: Self.now)
        #expect(result.deleted == 1 && store.deleted == ["9"])
    }
}
