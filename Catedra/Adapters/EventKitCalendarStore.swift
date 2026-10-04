import EventKit
import Foundation

/// EventKit implementation of `CalendarEventStoring`. Not exercised by tests (it would touch the user's calendars).
@MainActor
final class EventKitCalendarStore: CalendarEventStoring {
    private let store = EKEventStore()

    func requestAccess() async throws -> Bool {
        if EKEventStore.authorizationStatus(for: .event) == .fullAccess { return true }
        return try await store.requestFullAccessToEvents()
    }

    func calendarIdentifier(named name: String) throws -> String {
        if let existing = store.calendars(for: .event).first(where: { $0.title == name && $0.allowsContentModifications }) {
            return existing.calendarIdentifier
        }
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = name
        let sources = store.sources
        guard let source = store.defaultCalendarForNewEvents?.source ?? sources.first(where: { $0.sourceType == .local })
            ?? sources.first(where: { $0.sourceType == .calDAV }) else {
            throw EKStoreError.noWritableSource
        }
        calendar.source = source
        try store.saveCalendar(calendar, commit: true)
        return calendar.calendarIdentifier
    }

    func events(calendarID: String, from: Date, to: Date) throws -> [ExistingCalendarEvent] {
        guard let calendar = store.calendar(withIdentifier: calendarID) else { return [] }
        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: [calendar])
        return store.events(matching: predicate).compactMap { event in
            guard let id = event.eventIdentifier else { return nil }
            return ExistingCalendarEvent(identifier: id, entryID: CalendarMarker.entryID(in: event.notes), title: event.title ?? "",
                                         start: event.startDate, end: event.endDate, url: event.url, notes: event.notes ?? "")
        }
    }

    func create(_ event: ExportEvent, calendarID: String) throws {
        guard let calendar = store.calendar(withIdentifier: calendarID) else { throw EKStoreError.calendarMissing }
        let ek = EKEvent(eventStore: store)
        ek.calendar = calendar
        fill(ek, with: event)
        try store.save(ek, span: .thisEvent, commit: true)
    }

    func update(identifier: String, with event: ExportEvent) throws {
        guard let ek = store.event(withIdentifier: identifier) else { throw EKStoreError.eventMissing }
        fill(ek, with: event)
        try store.save(ek, span: .thisEvent, commit: true)
    }

    func delete(identifier: String) throws {
        guard let ek = store.event(withIdentifier: identifier) else { return }
        try store.remove(ek, span: .thisEvent, commit: true)
    }

    private func fill(_ ek: EKEvent, with event: ExportEvent) {
        ek.title = event.title
        ek.startDate = event.start
        ek.endDate = event.end
        ek.url = event.url
        ek.notes = CalendarMarker.notes(event.notes, entryID: event.entryID)
    }

    enum EKStoreError: Error, LocalizedError {
        case noWritableSource, calendarMissing, eventMissing

        var errorDescription: String? {
            switch self {
            case .noWritableSource: "No hay una cuenta de Calendario donde crear el calendario «Cátedra»."
            case .calendarMissing: "No se encontró el calendario «Cátedra»."
            case .eventMissing: "No se encontró el evento en Calendario."
            }
        }
    }
}
