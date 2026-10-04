import Testing
import SwiftUI
import AppKit
@testable import Catedra

/// Renders the week and month grids with fixture data. Set `TEST_RUNNER_CATEDRA_RENDER_DIR` to also write PNGs.
@MainActor
struct CalendarSnapshotTests {
    typealias F = CalendarFixtures

    static let courses = [Course(folderName: "01 - Teoria de Control II")!, Course(folderName: "02 - Electronica II")!,
                          Course(folderName: "03 - Sistemas Operativos")!]

    static func entries() -> [CalendarEntry] {
        func act(_ name: String, _ course: String, _ folder: String, due: Date?, cutoff: Date? = nil) -> Activity {
            Activity(courseName: course, kind: .tarea, name: name, due: due, rawStatus: "", grade: "", url: nil,
                     folder: "\(folder)/Tarea - \(name)", cutoff: cutoff)
        }
        let activities = [
            act("Informe de laboratorio 3", "Electronica II", "02 - Electronica II", due: F.date(5, 23, 59)),
            act("Parcial No. 2", "Teoria de Control II", "01 - Teoria de Control II", due: F.date(8, 23, 59)),
            act("Taller de Laplace", "Teoria de Control II", "01 - Teoria de Control II", due: F.date(8, 18, 0)),
            act("Foro de procesos", "Sistemas Operativos", "03 - Sistemas Operativos", due: F.date(8, 12, 0)),
            act("Quiz de semaforos", "Sistemas Operativos", "03 - Sistemas Operativos", due: F.date(9, 23, 59), cutoff: F.date(11, 23, 59)),
            act("Proyecto final", "Electronica II", "02 - Electronica II", due: F.date(21, 23, 59)),
        ]
        let events = [
            F.event(1, type: "meeting_start", module: "bigbluebuttonbn", start: F.date(6, 8), duration: 5400, course: "Teoria de Control II"),
            F.event(2, type: "meeting_start", module: "bigbluebuttonbn", start: F.date(8, 9), duration: 7200, course: "Electronica II"),
            F.event(3, type: "meeting_start", module: "bigbluebuttonbn", start: F.date(8, 10), duration: 3600, course: "Sistemas Operativos"),
            F.event(4, type: "meeting_start", module: "bigbluebuttonbn", start: F.date(10, 19), duration: 5400, course: "Electronica II"),
        ]
        let blocks = [
            StudyBlock(title: "Repasar Laplace", start: F.date(7, 15), end: F.date(7, 17), courseFolder: "01 - Teoria de Control II"),
            StudyBlock(title: "Practica de laboratorio", start: F.date(8, 14), end: F.date(8, 15, 30), courseFolder: "02 - Electronica II"),
            StudyBlock(title: "Leer capitulo 4", start: F.date(6, 20), end: F.date(6, 21), courseFolder: "03 - Sistemas Operativos", done: true),
        ]
        return CalendarBuilder.build(activities: activities, events: events.map { event in
            var e = event
            e = CalendarEvent(id: e.id, name: "Clase en vivo", courseId: e.courseId, courseName: e.courseName, eventType: e.eventType,
                              moduleName: e.moduleName, start: e.start, duration: e.duration, url: nil, cmid: nil)
            return e
        }, studyBlocks: blocks, courses: courses)
    }

    static func context(anchor: Date, entries: [CalendarEntry], now: Date) -> CalendarViewContext {
        CalendarViewContext(
            layout: CalendarLayout(calendar: F.cal), anchor: anchor, selectedDay: F.cal.startOfDay(for: F.date(8)), now: now,
            entries: entries,
            color: { entry in CoursePalette.color(for: courses.first { $0.folderName == entry.courseFolder }) },
            select: { _ in }, open: { _ in }, create: { _ in })
    }

    @discardableResult
    func render<V: View>(_ view: V, size: CGSize, name: String, dark: Bool = false) -> NSImage? {
        let content = view.frame(width: size.width, height: size.height)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, dark ? .dark : .light)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let image = renderer.nsImage else { return nil }
        if let dir = ProcessInfo.processInfo.environment["CATEDRA_RENDER_DIR"], let tiff = image.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
        return image
    }

    @Test func weekAndMonthRender() {
        let entries = Self.entries()
        let now = F.date(8, 11, 20)
        let ctx = Self.context(anchor: now, entries: entries, now: now)
        #expect(render(WeekGridView(context: ctx, scrolls: false), size: CGSize(width: 1000, height: 1000), name: "week") != nil)
        #expect(render(WeekGridView(context: ctx, scrolls: false), size: CGSize(width: 1000, height: 1000), name: "week-dark", dark: true) != nil)
        #expect(render(MonthGridView(context: ctx), size: CGSize(width: 1000, height: 700), name: "month") != nil)
        let empty = Self.context(anchor: now, entries: [], now: now)
        #expect(render(WeekGridView(context: empty, scrolls: false), size: CGSize(width: 1000, height: 1000), name: "week-empty") != nil)
    }
}
