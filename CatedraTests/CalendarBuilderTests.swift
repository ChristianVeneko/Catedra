import Testing
import Foundation
@testable import Catedra

enum CalendarFixtures {
    static var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Caracas")!
        c.firstWeekday = 2
        return c
    }

    static func date(_ d: Int, _ h: Int = 0, _ m: Int = 0, month: Int = 10) -> Date {
        cal.date(from: DateComponents(year: 2026, month: month, day: d, hour: h, minute: m))!
    }

    static func activity(_ name: String, folder: String = "01 - Control/Tarea", due: Date? = nil, opens: Date? = nil,
                         cutoff: Date? = nil, cmid: Int? = nil) -> Activity {
        Activity(courseName: "Control", kind: .tarea, name: name, due: due, rawStatus: "", grade: "", url: nil, folder: folder,
                 opens: opens, cutoff: cutoff, cmid: cmid)
    }

    static func event(_ id: Int, type: String = "due", module: String = "assign", start: Date, duration: TimeInterval = 0,
                      cmid: Int? = nil, course: String = "Control", url: String? = nil) -> CalendarEvent {
        CalendarEvent(id: id, name: "Evento \(id)", courseId: 1, courseName: course, eventType: type, moduleName: module,
                      start: start, duration: duration, url: url.flatMap(URL.init(string:)), cmid: cmid)
    }

    static let courses = [Course(folderName: "01 - Control")!]
}

struct CalendarBuilderTests {
    typealias F = CalendarFixtures

    @Test func activityDatesBecomeEntriesAndEqualCutoffIsSkipped() {
        let a = F.activity("T1", due: F.date(6, 23, 59), opens: F.date(1, 8), cutoff: F.date(6, 23, 59))
        let entries = CalendarBuilder.build(activities: [a], events: [], studyBlocks: [], courses: F.courses)
        #expect(entries.map(\.kind) == [.apertura, .entrega])
        #expect(entries.allSatisfy { $0.link == .activity(a.id) && $0.courseFolder == "01 - Control" })
    }

    @Test func cutoffAfterDueIsAClosingEntry() {
        let a = F.activity("T1", due: F.date(6, 23, 59), cutoff: F.date(8, 23, 59))
        let entries = CalendarBuilder.build(activities: [a], events: [], studyBlocks: [], courses: F.courses)
        #expect(entries.map(\.kind) == [.entrega, .cierre])
    }

    @Test func calendarEventMatchingActivityDateIsDeduplicated() {
        let a = F.activity("T1", due: F.date(6, 23, 59), cmid: 7)
        let dup = F.event(1, start: F.date(6, 23, 59), cmid: 7)
        let sameCmidOtherInstant = F.event(2, type: "close", start: F.date(9, 12), cmid: 7)
        let sameInstantOtherCmid = F.event(3, start: F.date(6, 23, 59), cmid: 8)
        let entries = CalendarBuilder.build(activities: [a], events: [dup, sameCmidOtherInstant, sameInstantOtherCmid],
                                            studyBlocks: [], courses: F.courses)
        #expect(entries.count == 3)
        #expect(!entries.contains { $0.id == "event:1" })
        #expect(entries.first { $0.id == "event:2" }?.kind == .cierre)
        #expect(entries.first { $0.id == "event:3" }?.kind == .entrega)
    }

    @Test func meetingsAreClassesWithUrlAndDuration() {
        let e = F.event(5, type: "meeting_start", module: "bigbluebuttonbn", start: F.date(7, 18), duration: 5400,
                        url: "https://saia/mod/bbb/view.php?id=9")
        let entry = CalendarBuilder.build(activities: [], events: [e], studyBlocks: [], courses: F.courses)[0]
        #expect(entry.kind == .clase)
        #expect(entry.end == F.date(7, 19, 30))
        #expect(entry.link == .url(URL(string: "https://saia/mod/bbb/view.php?id=9")!))
        #expect(entry.courseFolder == "01 - Control")
    }

    @Test func unknownEventTypeIsGenericEvent() {
        let e = F.event(6, type: "course", module: "", start: F.date(7, 9), course: "Otra")
        let entry = CalendarBuilder.build(activities: [], events: [e], studyBlocks: [], courses: F.courses)[0]
        #expect(entry.kind == .evento)
        #expect(entry.courseFolder == nil)
    }

    @Test func studyBlocksKeepCourseAndLink() {
        let b = StudyBlock(title: "Repasar", start: F.date(7, 15), end: F.date(7, 17), activityID: "01 - Control/Tarea")
        let entry = CalendarBuilder.build(activities: [], events: [], studyBlocks: [b], courses: F.courses)[0]
        #expect(entry.kind == .estudio)
        #expect(entry.link == .studyBlock(b.id))
        #expect(entry.courseFolder == "01 - Control" && entry.courseName == "Control")
        #expect(entry.end == F.date(7, 17))
    }

    @Test func sortedByStartThenTitle() {
        let a = F.activity("B", due: F.date(7, 10)), c = F.activity("A", folder: "01 - Control/A", due: F.date(7, 10))
        let early = F.activity("Z", folder: "01 - Control/Z", due: F.date(6, 10))
        let entries = CalendarBuilder.build(activities: [a, c, early], events: [], studyBlocks: [], courses: F.courses)
        #expect(entries.map(\.title) == ["Z", "A", "B"])
    }
}

struct CalendarLayoutTests {
    typealias F = CalendarFixtures
    let layout = CalendarLayout(calendar: F.cal)

    @Test func weekStartsOnMonday() {
        let days = layout.weekDays(containing: F.date(8, 15)) // Thursday 8 Oct 2026
        #expect(days.count == 7)
        #expect(days.first == F.date(5) && days.last == F.date(11))
    }

    @Test func monthGridCoversFullWeeks() {
        let weeks = layout.monthWeeks(containing: F.date(15))
        #expect(weeks.count == 5)
        #expect(weeks.first?.first == F.date(28, month: 9) && weeks.last?.last == F.date(1, month: 11))
        #expect(weeks.allSatisfy { $0.count == 7 })
    }

    @Test func lateEveningStaysOnItsLocalDay() {
        let a = F.activity("T", due: F.date(6, 23, 59))
        let entries = CalendarBuilder.build(activities: [a], events: [], studyBlocks: [], courses: F.courses)
        let byDay = layout.entriesByDay(entries)
        #expect(byDay[F.date(6)]?.count == 1)
        #expect(byDay[F.date(7)] == nil)
    }

    @Test func movesByWeekOrMonth() {
        #expect(layout.moved(F.date(8), mode: .week, by: 1) == F.date(15))
        #expect(layout.moved(F.date(8), mode: .month, by: -1) == F.date(8, month: 9))
    }

    @Test func weeklyLoadCountsDeadlinesAndStudyHours() {
        let acts = [F.activity("In", due: F.date(7, 12)), F.activity("Out", folder: "01 - Control/O", due: F.date(14, 12)),
                    F.activity("Open", folder: "01 - Control/P", opens: F.date(7, 8))]
        let blocks = [StudyBlock(title: "a", start: F.date(6, 9), end: F.date(6, 10, 30)),
                      StudyBlock(title: "b", start: F.date(13, 9), end: F.date(13, 11))]
        let entries = CalendarBuilder.build(activities: acts, events: [], studyBlocks: blocks, courses: F.courses)
        let load = layout.weeklyLoad(entries: entries, weekContaining: F.date(8))
        #expect(load.deadlines == 1)
        #expect(load.studyHours == 1.5)
    }
}

struct CalendarLanesTests {
    typealias F = CalendarFixtures

    func block(_ id: String, _ start: Date, _ end: Date) -> CalendarEntry {
        CalendarEntry(id: id, kind: .estudio, title: id, courseName: "", courseFolder: nil, start: start, end: end, link: nil)
    }

    @Test func overlappingEntriesShareLanesAndSeparateOnesDoNot() {
        let laned = CalendarLanes.assign([block("a", F.date(7, 9), F.date(7, 11)), block("b", F.date(7, 10), F.date(7, 12)),
                                          block("c", F.date(7, 15), F.date(7, 16))])
        let byID = Dictionary(uniqueKeysWithValues: laned.map { ($0.entry.id, $0) })
        #expect(byID["a"]?.lane == 0 && byID["b"]?.lane == 1)
        #expect(byID["a"]?.laneCount == 2 && byID["b"]?.laneCount == 2)
        #expect(byID["c"]?.lane == 0 && byID["c"]?.laneCount == 1)
    }
}

struct CalendarHourRangeTests {
    typealias F = CalendarFixtures
    let layout = CalendarLayout(calendar: F.cal)

    func timed(_ start: Date, _ end: Date?) -> CalendarEntry {
        CalendarEntry(id: "\(start.timeIntervalSince1970)", kind: .clase, title: "C", courseName: "Control", courseFolder: nil,
                      start: start, end: end, link: nil)
    }

    @Test func defaultsToSevenThroughTwentyThree() {
        #expect(layout.visibleHours(for: []) == 7..<23)
        #expect(layout.visibleHours(for: [timed(F.date(6, 9), F.date(6, 10))]) == 7..<23)
    }

    @Test func expandsForEarlyAndLateEntries() {
        let early = timed(F.date(6, 5, 30), F.date(6, 6, 30))
        let late = timed(F.date(6, 22), F.date(6, 23, 30))
        #expect(layout.visibleHours(for: [early, late]) == 5..<24)
    }

    @Test func entryRunningPastMidnightIsClamped() {
        #expect(layout.visibleHours(for: [timed(F.date(6, 22), F.date(7, 1))]) == 7..<24)
    }

    @Test func entryWithoutEndUsesDefaultDuration() {
        #expect(layout.visibleHours(for: [timed(F.date(6, 23), nil)]) == 7..<24)
    }
}

struct CalendarFormatTests {
    typealias F = CalendarFixtures

    @Test func clockIs24Hour() {
        #expect(CalendarFormat.clock(F.date(6, 23, 59)) == "23:59")
        #expect(CalendarFormat.clock(F.date(6, 7, 5)) == "07:05")
    }

    @Test func timeRangeJoinsStartAndEnd() {
        #expect(CalendarFormat.timeRange(F.date(6, 9), F.date(6, 10, 30)) == "09:00 – 10:30")
        #expect(CalendarFormat.timeRange(F.date(6, 9), nil) == "09:00")
    }

    @Test func weekRangeWithinOneMonth() {
        #expect(CalendarFormat.weekRange(first: F.date(5), last: F.date(11)) == "5 – 11 oct 2026")
    }

    @Test func weekRangeAcrossYearsShowsBothYears() {
        let first = F.cal.date(from: DateComponents(year: 2026, month: 12, day: 28))!
        let last = F.cal.date(from: DateComponents(year: 2027, month: 1, day: 3))!
        let text = CalendarFormat.weekRange(first: first, last: last)
        #expect(text.contains("2026") && text.contains("2027"))
    }
}
