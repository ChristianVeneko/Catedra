import Testing
import Foundation
@testable import Catedra

struct SubjectGroupingTests {
    static func ref(_ key: String, _ name: String) -> GradeCourseRef { GradeCourseRef(key: key, name: name) }
    let courses = [ref("05 - Electronica II", "Electronica II"), ref("06 - Laboratorio de Electronica II", "Laboratorio de Electronica II"),
                   ref("07 - Control", "Control")]

    @Test func ungroupedCoursesAreOwnSubjects() {
        let subjects = SubjectGrouping.subjects(courses: courses, groups: [])
        #expect(subjects.count == 3 && subjects.map(\.name) == ["Electronica II", "Laboratorio de Electronica II", "Control"])
    }

    @Test func groupMergesCoursesAndNamesAfterNonLab() {
        let subjects = SubjectGrouping.subjects(courses: courses, groups: [["06 - Laboratorio de Electronica II", "05 - Electronica II"]])
        #expect(subjects.count == 2)
        #expect(subjects[0].name == "Electronica II")
        #expect(subjects[0].courseKeys == ["05 - Electronica II", "06 - Laboratorio de Electronica II"])
        #expect(subjects[0].id == "05 - Electronica II|06 - Laboratorio de Electronica II")
    }

    @Test func staleOrOverlappingGroupsAreIgnored() {
        let subjects = SubjectGrouping.subjects(courses: courses, groups: [["05 - Electronica II", "99 - Gone"], ["06 - Laboratorio de Electronica II", "07 - Control"],
                                                                         ["07 - Control", "05 - Electronica II"]])
        // first group has a single live course -> not a merge; second wins over the third for Control
        #expect(subjects.map(\.courseKeys) == [["05 - Electronica II"], ["06 - Laboratorio de Electronica II", "07 - Control"]])
    }

    @Test func suggestsLaboratoryMatchesAccentAndCaseInsensitively() {
        let list = [Self.ref("01 - Electrónica II", "Electrónica II"), Self.ref("02 - LABORATORIO DE ELECTRONICA II", "LABORATORIO DE ELECTRONICA II"),
                    Self.ref("03 - Laboratorio de Física", "Laboratorio de Física")]
        let found = SubjectGrouping.suggestions(courses: list, groups: [], dismissed: [])
        #expect(found == [SubjectSuggestion(courseKeys: ["01 - Electrónica II", "02 - LABORATORIO DE ELECTRONICA II"])])
    }

    @Test func suggestionsSkipGroupedAndDismissedPairs() {
        let pair = ["05 - Electronica II", "06 - Laboratorio de Electronica II"]
        #expect(SubjectGrouping.suggestions(courses: courses, groups: [pair], dismissed: []).isEmpty)
        let found = SubjectGrouping.suggestions(courses: courses, groups: [], dismissed: [SubjectGrouping.suggestionKey(pair.reversed())])
        #expect(found.isEmpty)
        #expect(SubjectGrouping.suggestions(courses: courses, groups: [], dismissed: []).count == 1)
    }
}

struct GradeCourseResolverTests {
    typealias G = GradeFixtures
    let courses = [Course(folderName: "05 - Electronica II")!, Course(folderName: "07 - Control")!]

    func activity(_ folder: String, cmid: Int?) -> Activity {
        Activity(courseName: "x", kind: .tarea, name: "a", due: nil, rawStatus: "", grade: "", url: nil, folder: folder, cmid: cmid)
    }

    @Test func resolvesByMajorityOfMatchingCmids() {
        let report = GradeReport(courseId: 9, items: [G.item("A", cmid: 1), G.item("B", cmid: 2), G.item("C", cmid: 3)], total: nil)
        let acts = [activity("07 - Control/x", cmid: 1), activity("05 - Electronica II/y", cmid: 2), activity("05 - Electronica II/z", cmid: 3)]
        #expect(GradeCourseResolver.folder(for: report, activities: acts, events: [], courses: courses) == "05 - Electronica II")
    }

    @Test func fallsBackToCalendarEventCourseName() {
        let report = GradeReport(courseId: 9, items: [G.item("Manual", type: "manual")], total: nil)
        let ev = CalendarEvent(id: 1, name: "", courseId: 9, courseName: "CONTROL", eventType: "due", moduleName: "", start: Date(timeIntervalSince1970: 0),
                               duration: 0, url: nil, cmid: nil)
        #expect(GradeCourseResolver.folder(for: report, activities: [], events: [ev], courses: courses) == "07 - Control")
    }

    @Test func unresolvedReturnsNil() {
        let report = GradeReport(courseId: 9, items: [], total: nil)
        #expect(GradeCourseResolver.folder(for: report, activities: [], events: [], courses: courses) == nil)
    }
}

struct GradeDashboardTests {
    typealias G = GradeFixtures

    @Test func buildsSubjectsWithGroupedLinesAndPerSubjectTarget() {
        let courses = [Course(folderName: "05 - Electronica II")!, Course(folderName: "06 - Laboratorio de Electronica II")!]
        func act(_ folder: String, _ cmid: Int) -> Activity {
            Activity(courseName: "x", kind: .tarea, name: "a", due: nil, rawStatus: "", grade: "", url: nil, folder: folder, cmid: cmid)
        }
        let reports = [
            GradeReport(courseId: 1, items: [G.item("Parcial", raw: 20, max: 50, cmid: 10)], total: nil),
            GradeReport(courseId: 2, items: [G.item("Informe", raw: 10, max: 25, cmid: 20), G.item("Informe 2", max: 25, cmid: 21)], total: nil),
        ]
        let activities = [act("05 - Electronica II/p", 10), act("06 - Laboratorio de Electronica II/i", 20)]
        var settings = GradeSettings()
        settings.group(["05 - Electronica II", "06 - Laboratorio de Electronica II"])
        settings.setTarget(60, forSubject: "05 - Electronica II|06 - Laboratorio de Electronica II")
        settings.toggleExcluded("06 - Laboratorio de Electronica II#cmid21")
        let result = GradeDashboard.build(reports: reports, activities: activities, events: [], courses: courses, settings: settings)
        #expect(result.count == 1)
        #expect(result[0].subject.name == "Electronica II")
        #expect(result[0].lines.count == 3)
        #expect(result[0].summary.earned == 30 && result[0].summary.totalPossible == 75 && result[0].summary.targetPercent == 60)
    }

    @Test func subjectsWithoutReportsAreHiddenAndUnresolvedReportsKept() {
        let courses = [Course(folderName: "05 - A")!, Course(folderName: "06 - B")!]
        let reports = [GradeReport(courseId: 77, items: [G.item("X", raw: 1, max: 2)], total: nil)]
        let result = GradeDashboard.build(reports: reports, activities: [], events: [], courses: courses, settings: GradeSettings())
        #expect(result.count == 1 && result[0].subject.name == "Curso 77")
    }
}

struct GradeSettingsTests {
    func tempFile() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("catedra-\(UUID().uuidString)/grade-settings.json")
    }

    @Test func defaultTargetIsFiftyPercent() {
        #expect(GradeSettings().target(forSubject: "any") == 50)
    }

    @Test func targetIsClampedAndStoredPerSubject() {
        var s = GradeSettings()
        s.setTarget(70, forSubject: "a")
        s.setTarget(150, forSubject: "b")
        s.setTarget(-5, forSubject: "c")
        #expect(s.target(forSubject: "a") == 70 && s.target(forSubject: "b") == 100 && s.target(forSubject: "c") == 0)
    }

    @Test func toggleExcludedFlipsMembership() {
        var s = GradeSettings()
        s.toggleExcluded("k#1"); #expect(s.excludedItems == ["k#1"])
        s.toggleExcluded("k#1"); #expect(s.excludedItems.isEmpty)
    }

    @Test func groupingMovesCoursesAndDropsSingletons() {
        var s = GradeSettings()
        s.group(["a", "b"])
        s.group(["b", "c"])
        #expect(s.groups == [["b", "c"]])
        s.ungroup("b")
        #expect(s.groups.isEmpty)
    }

    @Test func roundTrip() throws {
        let store = JSONGradeSettingsStore(file: tempFile())
        var s = GradeSettings()
        s.group(["a", "b"]); s.setTarget(65, forSubject: "a|b"); s.toggleExcluded("a#cmid3"); s.dismissSuggestion(["x", "y"])
        try store.save(s)
        #expect(store.load() == s)
    }

    @Test func missingOrMalformedFileGivesDefaults() throws {
        let file = tempFile()
        #expect(JSONGradeSettingsStore(file: file).load() == GradeSettings())
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("nope".utf8).write(to: file)
        #expect(JSONGradeSettingsStore(file: file).load() == GradeSettings())
    }

    @Test func partialFileKeepsKnownKeys() throws {
        let file = tempFile()
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"targets":{"a":80},"future":1}"#.utf8).write(to: file)
        let s = JSONGradeSettingsStore(file: file).load()
        #expect(s.target(forSubject: "a") == 80 && s.groups.isEmpty && s.excludedItems.isEmpty)
    }
}
