import Foundation

enum CalendarExportError: Error, Equatable, LocalizedError {
    case accessDenied

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            "Cátedra no tiene permiso para usar Calendario. Actívelo en Ajustes del Sistema > Privacidad y seguridad > Calendarios."
        }
    }
}

struct CalendarExportResult: Equatable, Sendable {
    var created = 0, updated = 0, deleted = 0, unchanged = 0

    var summary: String {
        if created + updated + deleted == 0 { return "Calendario al día (\(unchanged) eventos)." }
        return "Calendario actualizado: \(created) nuevos, \(updated) modificados, \(deleted) eliminados."
    }
}

/// Upserts deadlines, classes and study blocks into the "Cátedra" calendar without creating duplicates.
@MainActor
struct CalendarExportUseCase {
    static let calendarName = "Cátedra"
    static let pastWindow: TimeInterval = 30 * 86400
    static let futureWindow: TimeInterval = 365 * 86400

    let store: CalendarEventStoring

    func export(entries: [CalendarEntry], now: Date) async throws -> CalendarExportResult {
        guard try await store.requestAccess() else { throw CalendarExportError.accessDenied }
        let from = now.addingTimeInterval(-Self.pastWindow), to = now.addingTimeInterval(Self.futureWindow)
        let calendarID = try store.calendarIdentifier(named: Self.calendarName)
        let existing = try store.events(calendarID: calendarID, from: from, to: to)
        let plan = CalendarExportPlanner.plan(desired: CalendarExportPlanner.events(from: entries, window: from..<to), existing: existing)
        for event in plan.create { try store.create(event, calendarID: calendarID) }
        for update in plan.update { try store.update(identifier: update.identifier, with: update.event) }
        for id in plan.delete { try store.delete(identifier: id) }
        return CalendarExportResult(created: plan.create.count, updated: plan.update.count, deleted: plan.delete.count,
                                    unchanged: plan.unchanged)
    }
}
