import Foundation

/// Event to write in the system calendar. `entryID` is the stable `CalendarEntry.id`.
struct ExportEvent: Equatable, Sendable {
    let entryID: String
    let title: String
    let start: Date
    let end: Date
    let url: URL?
    /// User-facing notes, without the marker.
    let notes: String
}

/// An event already in the "Cátedra" calendar. `entryID` is parsed from the marker in `notes`.
struct ExistingCalendarEvent: Equatable, Sendable {
    let identifier: String
    let entryID: String?
    let title: String
    let start: Date
    let end: Date
    let url: URL?
    let notes: String
}

struct ExportUpdate: Equatable, Sendable {
    let identifier: String
    let event: ExportEvent
}

struct ExportPlan: Equatable, Sendable {
    var create: [ExportEvent] = []
    var update: [ExportUpdate] = []
    var delete: [String] = []
    var unchanged = 0
}

/// Stable marker stored in the event notes so re-exports find their own events.
enum CalendarMarker {
    static let prefix = "catedra-id:"

    static func notes(_ notes: String, entryID: String) -> String {
        (notes.isEmpty ? "" : notes + "\n\n") + prefix + entryID
    }

    static func entryID(in notes: String?) -> String? {
        guard let notes else { return nil }
        for line in notes.split(separator: "\n", omittingEmptySubsequences: true).reversed() where line.hasPrefix(prefix) {
            return String(line.dropFirst(prefix.count))
        }
        return nil
    }
}

enum CalendarExportPlanner {
    static let deadlineLead: TimeInterval = 1800
    static let defaultDuration: TimeInterval = 3600

    /// Deadlines, classes and study blocks inside `window`, as calendar events.
    static func events(from entries: [CalendarEntry], window: Range<Date>) -> [ExportEvent] {
        entries.compactMap { entry in
            guard window.contains(entry.start) else { return nil }
            let start: Date, end: Date, title: String
            switch entry.kind {
            case .entrega, .cierre:
                end = entry.start
                start = end.addingTimeInterval(-deadlineLead)
                title = "\(entry.kind.label): \(entry.title)"
            case .clase, .estudio:
                start = entry.start
                end = entry.end.flatMap { $0 > start ? $0 : nil } ?? start.addingTimeInterval(defaultDuration)
                title = "\(entry.kind.label): \(entry.title)"
            case .apertura, .evento:
                return nil
            }
            var link: URL?
            if case .url(let url) = entry.link { link = url }
            return ExportEvent(entryID: entry.id, title: title, start: start, end: end, url: link, notes: entry.courseName)
        }
    }

    static func plan(desired: [ExportEvent], existing: [ExistingCalendarEvent]) -> ExportPlan {
        var plan = ExportPlan()
        var byEntry: [String: [ExistingCalendarEvent]] = [:]
        for e in existing { if let id = e.entryID { byEntry[id, default: []].append(e) } }
        let desiredIDs = Set(desired.map(\.entryID))

        for event in desired {
            let found = byEntry[event.entryID] ?? []
            guard let primary = found.first else { plan.create.append(event); continue }
            plan.delete += found.dropFirst().map(\.identifier)
            if matches(primary, event) { plan.unchanged += 1 } else { plan.update.append(ExportUpdate(identifier: primary.identifier, event: event)) }
        }
        for e in existing {
            if let id = e.entryID, !desiredIDs.contains(id) { plan.delete.append(e.identifier) }
        }
        return plan
    }

    private static func matches(_ existing: ExistingCalendarEvent, _ event: ExportEvent) -> Bool {
        existing.title == event.title && existing.url == event.url
            && abs(existing.start.timeIntervalSince(event.start)) < 1 && abs(existing.end.timeIntervalSince(event.end)) < 1
            && existing.notes == CalendarMarker.notes(event.notes, entryID: event.entryID)
    }
}
