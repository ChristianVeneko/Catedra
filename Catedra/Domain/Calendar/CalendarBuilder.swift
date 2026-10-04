import Foundation

/// Merges activity dates, Moodle calendar events and study blocks into one sorted list. Pure.
enum CalendarBuilder {
    static let defaultClassDuration: TimeInterval = 3600

    static func build(activities: [Activity], events: [CalendarEvent], studyBlocks: [StudyBlock], courses: [Course]) -> [CalendarEntry] {
        var entries: [CalendarEntry] = []
        var datesByCmid: [Int: Set<Date>] = [:]
        var folderByCmid: [Int: String] = [:]
        var folderByCourseName: [String: String] = [:]

        for course in courses { folderByCourseName[fold(course.name)] = course.folderName }
        for a in activities {
            folderByCourseName[fold(a.courseName)] = a.courseFolderName
            if let cmid = a.cmid {
                folderByCmid[cmid] = a.courseFolderName
                datesByCmid[cmid, default: []].formUnion([a.due, a.opens, a.cutoff].compactMap { $0 })
            }
            var seen: Set<Date> = []
            for (kind, date) in [(CalendarEntryKind.apertura, a.opens), (.entrega, a.due), (.cierre, a.cutoff)] {
                guard let date, seen.insert(date).inserted else { continue }
                entries.append(CalendarEntry(id: "activity:\(a.id):\(kind.rawValue)", kind: kind, title: a.name,
                                             courseName: a.courseName, courseFolder: a.courseFolderName, start: date, end: nil,
                                             link: .activity(a.id)))
            }
        }

        for e in events {
            if let cmid = e.cmid, datesByCmid[cmid]?.contains(e.start) == true { continue }
            let kind = kind(of: e)
            let folder = e.cmid.flatMap { folderByCmid[$0] } ?? folderByCourseName[fold(e.courseName)]
            var end: Date?
            if kind == .clase { end = e.start.addingTimeInterval(e.duration > 0 ? e.duration : defaultClassDuration) }
            else if e.duration > 0 { end = e.start.addingTimeInterval(e.duration) }
            entries.append(CalendarEntry(id: "event:\(e.id)", kind: kind, title: e.name, courseName: e.courseName,
                                         courseFolder: folder, start: e.start, end: end, link: e.url.map { .url($0) }))
        }

        for b in studyBlocks {
            let folder = b.courseFolder ?? b.activityID.flatMap { $0.split(separator: "/").first.map(String.init) }
            let course = courses.first { $0.folderName == folder }
            entries.append(CalendarEntry(id: "study:\(b.id.uuidString)", kind: .estudio, title: b.title,
                                         courseName: course?.name ?? "", courseFolder: folder, start: b.start, end: b.end,
                                         link: .studyBlock(b.id), isDone: b.done))
        }

        return entries.sorted { ($0.start, $0.title, $0.id) < ($1.start, $1.title, $1.id) }
    }

    static func kind(of event: CalendarEvent) -> CalendarEntryKind {
        if event.eventType.hasPrefix("meeting") || event.moduleName == "bigbluebuttonbn" { return .clase }
        switch event.eventType {
        case "due": return .entrega
        case "close": return .cierre
        case "open": return .apertura
        default: return .evento
        }
    }

    private static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).trimmingCharacters(in: .whitespaces)
    }
}
