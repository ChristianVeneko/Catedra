import Testing
import Foundation
@testable import Catedra

struct PhaseFourDataTests {
    static let gradesJSON = """
    {"courseid":5,"items":[
      {"itemname":"Tarea 1","itemtype":"mod","itemmodule":"assign","cmid":77,"graderaw":8.5,"gradeformatted":"8,50",
       "grademin":0,"grademax":10,"weightraw":20.0,"percentageformatted":"85 %","feedback":"Bien",
       "gradedatesubmitted":100,"gradedategraded":200},
      {"itemname":"Quiz","itemtype":"mod","grademax":20}],
     "total":{"itemname":"","itemtype":"course","graderaw":8.5,"grademax":100}}
    """

    @Test func decodesGradeReport() throws {
        let r = try GradeReportDecoder.decode(Data(Self.gradesJSON.utf8))
        #expect(r.courseId == 5)
        #expect(r.items.count == 2)
        #expect(r.items[0].gradeRaw == 8.5 && r.items[0].weight == 20 && r.items[0].cmid == 77)
        #expect(r.items[0].gradedAt == Date(timeIntervalSince1970: 200))
        #expect(r.items[1].gradeRaw == nil && r.items[1].weight == nil && r.items[1].feedback.isEmpty)
        #expect(r.total?.gradeMax == 100)
    }

    @Test func decodesCalendarSortedAndTolerant() throws {
        let json = """
        [{"id":2,"name":"B","timestart":2000,"url":"https://x/mod/assign/view.php?id=7","cmid":7,"course":"C","courseid":5},
         {"id":1,"timestart":1000}]
        """
        let ev = try CalendarEventDecoder.decode(Data(json.utf8))
        #expect(ev.map(\.id) == [1, 2])
        #expect(ev[0].name.isEmpty && ev[0].url == nil && ev[0].duration == 0)
        #expect(ev[1].cmid == 7 && ev[1].courseName == "C" && ev[1].url != nil)
    }

    private func workspace(extra: (URL) throws -> Void) throws -> WorkspaceSnapshot {
        let root = try makeTempDirectory()
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("_sistema/data"), withIntermediateDirectories: true)
        let folder = "01 - X/actividades/Tarea - T"
        try fm.createDirectory(at: root.appendingPathComponent(folder), withIntermediateDirectories: true)
        let json = #"[{"course":"X","type":"Tarea","name":"T","due":0,"folder":"\#(folder)"}]"#
        try json.write(to: root.appendingPathComponent("_sistema/data/activities.json"), atomically: true, encoding: .utf8)
        try extra(root)
        return try FileSystemWorkspace().loadSnapshot(root: root)
    }

    @Test func missingFilesGiveEmptyCollections() throws {
        let snap = try workspace { _ in }
        #expect(snap.gradeReports.isEmpty && snap.calendarEvents.isEmpty && snap.activitiesWithRubric.isEmpty)
    }

    @Test func loadsGradesCalendarAndRubricFlag() throws {
        let snap = try workspace { root in
            let data = root.appendingPathComponent("_sistema/data")
            try Self.gradesJSON.write(to: data.appendingPathComponent("grades_5.json"), atomically: true, encoding: .utf8)
            try #"[{"id":1,"timestart":10}]"#.write(to: data.appendingPathComponent("calendar.json"), atomically: true, encoding: .utf8)
            try "# Rubrica".write(to: root.appendingPathComponent("01 - X/actividades/Tarea - T/rubrica.md"), atomically: true, encoding: .utf8)
        }
        #expect(snap.gradeReports.map(\.courseId) == [5])
        #expect(snap.calendarEvents.count == 1)
        #expect(snap.activitiesWithRubric == ["01 - X/actividades/Tarea - T"])
    }

    @Test func malformedFilesGiveEmptyNotCrash() throws {
        let snap = try workspace { root in
            let data = root.appendingPathComponent("_sistema/data")
            try "{".write(to: data.appendingPathComponent("grades_5.json"), atomically: true, encoding: .utf8)
            try "nope".write(to: data.appendingPathComponent("calendar.json"), atomically: true, encoding: .utf8)
        }
        #expect(snap.gradeReports.isEmpty && snap.calendarEvents.isEmpty)
        #expect(snap.activities.count == 1)
    }

    @Test func activityFilesReportsRubric() throws {
        let root = try makeTempDirectory()
        let dir = root.appendingPathComponent("c/a")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let activity = makeActivity(folder: "c/a")
        #expect(!FileSystemWorkspace().files(root: root, activity: activity).hasRubric)
        try "x".write(to: dir.appendingPathComponent("rubrica.md"), atomically: true, encoding: .utf8)
        #expect(FileSystemWorkspace().files(root: root, activity: activity).hasRubric)
    }
}
