import Foundation

enum CalendarEntryKind: String, Hashable, Sendable, CaseIterable {
    case entrega, apertura, cierre, clase, evento, estudio

    var label: String {
        switch self {
        case .entrega: "Entrega"
        case .apertura: "Apertura"
        case .cierre: "Cierre"
        case .clase: "Clase"
        case .evento: "Evento"
        case .estudio: "Estudio"
        }
    }

    var symbolName: String {
        switch self {
        case .entrega: "flag.fill"
        case .apertura: "lock.open"
        case .cierre: "lock"
        case .clase: "video"
        case .evento: "calendar"
        case .estudio: "book"
        }
    }

    /// Timed entries live in the hours grid; the rest go to the all-day/deadline strip.
    var isTimed: Bool { self == .clase || self == .estudio }

    /// Counts as a deadline in the weekly load.
    var isDeadline: Bool { self == .entrega || self == .cierre }
}

enum CalendarEntryLink: Hashable, Sendable {
    case activity(String)
    case url(URL)
    case studyBlock(UUID)
}

struct CalendarEntry: Identifiable, Hashable, Sendable {
    let id: String
    let kind: CalendarEntryKind
    let title: String
    let courseName: String
    /// Folder of the matching course, when known (drives the color).
    let courseFolder: String?
    let start: Date
    let end: Date?
    let link: CalendarEntryLink?
    var isDone = false

    var duration: TimeInterval { end.map { max(0, $0.timeIntervalSince(start)) } ?? 0 }
}
