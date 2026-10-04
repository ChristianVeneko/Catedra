import Foundation

protocol StudyBlockStoring: Sendable {
    func load() -> [StudyBlock]
    func save(_ blocks: [StudyBlock]) throws
}

/// The system calendar (EventKit). Only touches the dedicated calendar it creates.
@MainActor
protocol CalendarEventStoring {
    /// Asks for full calendar access; shows the system prompt only while undetermined.
    func requestAccess() async throws -> Bool
    /// Identifier of the calendar called `named`, creating it when missing.
    func calendarIdentifier(named: String) throws -> String
    func events(calendarID: String, from: Date, to: Date) throws -> [ExistingCalendarEvent]
    func create(_ event: ExportEvent, calendarID: String) throws
    func update(identifier: String, with event: ExportEvent) throws
    func delete(identifier: String) throws
}
