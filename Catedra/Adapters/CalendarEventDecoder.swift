import Foundation

/// Decodes `calendar.json` (a JSON array of normalized events), sorted by start time.
enum CalendarEventDecoder {
    private struct Record: Decodable {
        let id: Int
        let name: String?
        let courseid: Int?
        let course: String?
        let eventtype: String?
        let modulename: String?
        let timestart: Int
        let timeduration: Int?
        let url: String?
        let cmid: Int?
    }

    static func decode(_ data: Data) throws -> [CalendarEvent] {
        try JSONDecoder().decode([Record].self, from: data).map { r in
            CalendarEvent(
                id: r.id, name: r.name ?? "", courseId: r.courseid, courseName: r.course ?? "",
                eventType: r.eventtype ?? "", moduleName: r.modulename ?? "",
                start: Date(timeIntervalSince1970: TimeInterval(r.timestart)),
                duration: TimeInterval(r.timeduration ?? 0),
                url: (r.url?.isEmpty == false) ? URL(string: r.url!) : nil, cmid: r.cmid)
        }.sorted { $0.start < $1.start }
    }
}
