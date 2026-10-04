import Testing
import Foundation
@testable import Catedra

struct GradeChangeTests {
    typealias G = GradeFixtures

    func activity(_ name: String, grade: String = "", feedback: String = "", cmid: Int? = nil, course: String = "Control") -> Activity {
        Activity(courseName: course, kind: .tarea, name: name, due: nil, rawStatus: "", grade: grade, url: nil,
                 folder: "01 - Control/\(name)", feedback: feedback, cmid: cmid)
    }

    func snapshot(activities: [Activity] = [], reports: [GradeReport] = []) -> WorkspaceSnapshot {
        WorkspaceSnapshot(courses: [Course(folderName: "01 - Control")!], activities: activities, activitiesWithUserWork: [],
                          lastSync: nil, gradeReports: reports)
    }

    func report(_ items: [GradeItem]) -> GradeReport { GradeReport(courseId: 1, items: items, total: nil) }

    @Test func newGradeInReportIsDetected() {
        let before = snapshot(activities: [activity("T", cmid: 5)], reports: [report([G.item("T", cmid: 5)])])
        let after = snapshot(activities: [activity("T", cmid: 5)], reports: [report([G.item("T", raw: 18, cmid: 5)])])
        let changes = GradeChangeDetector.changes(before: before, after: after)
        #expect(changes.count == 1 && changes[0].kind == .newGrade && changes[0].itemName == "T" && changes[0].courseName == "Control")
    }

    @Test func changedGradeAndNewFeedbackAreDetected() {
        let before = snapshot(reports: [report([G.item("T", raw: 10, cmid: 5), G.item("U", raw: 12, cmid: 6)])])
        let after = snapshot(reports: [report([G.item("T", raw: 14, cmid: 5), G.item("U", raw: 12, cmid: 6, feedback: "Buen trabajo")])])
        let kinds = GradeChangeDetector.changes(before: before, after: after).map(\.kind)
        #expect(kinds == [.gradeChanged, .feedback])
    }

    @Test func unchangedReportsProduceNothing() {
        let s = snapshot(reports: [report([G.item("T", raw: 10, cmid: 5, feedback: "ok")])])
        #expect(GradeChangeDetector.changes(before: s, after: s).isEmpty)
    }

    @Test func firstSyncDoesNotFloodWithNotifications() {
        let after = snapshot(activities: [activity("T", grade: "18", cmid: 5)], reports: [report([G.item("T", raw: 18, cmid: 5)])])
        #expect(GradeChangeDetector.changes(before: snapshot(), after: after).isEmpty)
    }

    @Test func newItemWithGradeInKnownCourseCounts() {
        let before = snapshot(reports: [report([G.item("T", raw: 10, cmid: 5)])])
        let after = snapshot(reports: [report([G.item("T", raw: 10, cmid: 5), G.item("Nuevo", raw: 7, cmid: 6)])])
        #expect(GradeChangeDetector.changes(before: before, after: after).map(\.itemName) == ["Nuevo"])
    }

    @Test func categoryRowsAreIgnored() {
        let before = snapshot(reports: [report([G.item("", type: "category")])])
        let after = snapshot(reports: [report([G.item("", raw: 5, type: "category")])])
        #expect(GradeChangeDetector.changes(before: before, after: after).isEmpty)
    }

    @Test func activityGradeAndFeedbackChangesAreDetected() {
        let before = snapshot(activities: [activity("A"), activity("B", grade: "10"), activity("C")])
        let after = snapshot(activities: [activity("A", grade: "17,5"), activity("B", grade: "12"), activity("C", feedback: "Revisar")])
        #expect(GradeChangeDetector.changes(before: before, after: after).map(\.kind) == [.newGrade, .gradeChanged, .feedback])
    }

    @Test func activityChangeIsDroppedWhenReportAlreadyCoversItsCmid() {
        let before = snapshot(activities: [activity("T", cmid: 5)], reports: [report([G.item("T", cmid: 5)])])
        let after = snapshot(activities: [activity("T", grade: "18", cmid: 5)], reports: [report([G.item("T", raw: 18, cmid: 5)])])
        #expect(GradeChangeDetector.changes(before: before, after: after).count == 1)
    }

    @Test func notificationContentSingularAndPlural() {
        let one = GradeChange(kind: .newGrade, itemName: "Parcial 1", courseName: "Control", grade: "18")
        let content = GradeChangeNotification.content(for: [one])
        #expect(content?.title == "Cátedra: nueva nota" && content?.body == "Control · Parcial 1: 18")
        let fb = GradeChange(kind: .feedback, itemName: "Taller", courseName: "Control", grade: "")
        #expect(GradeChangeNotification.content(for: [fb])?.title == "Cátedra: nueva retroalimentación")
        let many = GradeChangeNotification.content(for: [one, fb])
        #expect(many?.title == "Cátedra: novedades en sus notas" && many?.body.contains("2") == true)
        #expect(GradeChangeNotification.content(for: []) == nil)
    }

    @Test func policyDefaultsToPermissionWhenUnset() {
        #expect(GradeChangeNotification.isEnabled(preference: nil, permission: .authorized))
        #expect(!GradeChangeNotification.isEnabled(preference: nil, permission: .notDetermined))
        #expect(!GradeChangeNotification.isEnabled(preference: nil, permission: .denied))
        #expect(GradeChangeNotification.isEnabled(preference: true, permission: .denied))
        #expect(!GradeChangeNotification.isEnabled(preference: false, permission: .authorized))
    }

    @Test func syncSummaryMentionsGradeChanges() {
        var diff = ActivityDiff()
        diff.gradeChanges = [GradeChange(kind: .newGrade, itemName: "A", courseName: "C", grade: "1")]
        #expect(!diff.isEmpty)
        #expect(SyncSummary.text(for: diff) == "1 nota nueva")
    }
}

struct GradeNeedTextTests {
    typealias G = GradeFixtures

    func text(_ lines: [GradeLine], target: Double = 50) -> String {
        let s = GradeCalculator.summary(lines: lines, targetPercent: target)
        return GradeNeedText.describe(summary: s, targetPercent: target)
    }

    @Test func passedMentionsTarget() {
        #expect(text([G.line("P1", earned: 50, max: 50), G.line("P2", max: 50)]) == "Ya alcanzó la meta de 50 pts.")
    }

    @Test func requiredAverageOverRemaining() {
        #expect(text([G.line("P1", earned: 10, max: 40), G.line("P2", max: 60)]) == "Necesita 40 pts de los 60 que quedan: un promedio de 66,7 % en lo pendiente.")
    }

    @Test func unreachableExplainsBestCase() {
        #expect(text([G.line("P1", earned: 5, max: 60), G.line("P2", max: 30)]) == "La meta de 45 pts ya no es alcanzable: con el máximo en lo pendiente llegaría a 35 pts.")
    }

    @Test func nothingRemainingBelowTarget() {
        #expect(text([G.line("P1", earned: 10, max: 50), G.line("P2", earned: 10, max: 50)]) == "No quedan evaluaciones pendientes y los 20 pts no alcanzan la meta de 50 pts.")
    }

    @Test func noDataIsExplained() {
        #expect(text([]) == "Aún no hay evaluaciones con puntos.")
    }
}
