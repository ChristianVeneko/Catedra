import Testing
import Foundation
@testable import Catedra

struct WeeklyDigestTests {
    /// 2026-10-05 is a Monday; Caracas is UTC-4 (no DST), so 07:00 there is 11:00 UTC.
    func caracas(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    @Test func weekKeyIsTheIsoWeekInCaracas() {
        #expect(WeeklySchedule.weekKey(for: caracas("2026-10-05T11:00:00Z")) == "2026-W41")
        // Sunday night in Caracas is still the previous week even though UTC is already Monday.
        #expect(WeeklySchedule.weekKey(for: caracas("2026-10-05T02:00:00Z")) == "2026-W40")
    }

    @Test func dueFromMondaySevenAmOncePerWeek() {
        let beforeSeven = caracas("2026-10-05T10:59:00Z")
        let atSeven = caracas("2026-10-05T11:00:00Z")
        let wednesday = caracas("2026-10-07T20:00:00Z")
        #expect(!WeeklySchedule.isDue(now: beforeSeven, lastWeekKey: nil, enabled: true))
        #expect(WeeklySchedule.isDue(now: atSeven, lastWeekKey: nil, enabled: true))
        #expect(WeeklySchedule.isDue(now: wednesday, lastWeekKey: "2026-W40", enabled: true))
        #expect(!WeeklySchedule.isDue(now: wednesday, lastWeekKey: "2026-W41", enabled: true))
        #expect(!WeeklySchedule.isDue(now: wednesday, lastWeekKey: nil, enabled: false))
    }

    @Test func sundayLaunchBeforeTheNextMondayIsNotDue() {
        // Sunday 23:00 Caracas of week 41 with week 41 already done.
        #expect(!WeeklySchedule.isDue(now: caracas("2026-10-12T03:00:00Z"), lastWeekKey: "2026-W41", enabled: true))
    }

    func digest() -> WeeklyDigest {
        let now = caracas("2026-10-07T16:00:00Z")
        let inWeek = makeActivity(name: "Informe", due: caracas("2026-10-09T20:00:00Z"))
        let early = makeActivity(name: "Antes", due: caracas("2026-10-02T20:00:00Z"), folder: "08 - X/actividades/Antes")
        let later = makeActivity(name: "Luego", due: caracas("2026-10-14T20:00:00Z"), folder: "08 - X/actividades/Luego")
        let done = makeActivity(name: "Hecha", due: caracas("2026-10-08T20:00:00Z"), folder: "08 - X/actividades/Hecha")
        let grades = [
            GradeEntry(name: "Parcial", courseName: "Control", grade: "18", gradedAt: caracas("2026-09-30T12:00:00Z")),
            GradeEntry(name: "Parcial", courseName: "Control", grade: "18", gradedAt: caracas("2026-09-30T12:00:00Z")),
            GradeEntry(name: "Vieja", courseName: "Control", grade: "10", gradedAt: caracas("2026-09-01T12:00:00Z")),
            GradeEntry(name: "Sin fecha", courseName: "Control", grade: "9", gradedAt: nil),
        ]
        let blocks = [
            StudyBlock(title: "Repasar", start: caracas("2026-10-06T14:00:00Z"), end: caracas("2026-10-06T15:00:00Z")),
            StudyBlock(title: "Otra semana", start: caracas("2026-10-14T14:00:00Z"), end: caracas("2026-10-14T15:00:00Z")),
        ]
        return WeeklyDigestBuilder.build(now: now, activities: [later, inWeek, early, done], isOpen: { $0.name != "Hecha" },
                                         grades: grades, studyBlocks: blocks, cardsDue: 4)
    }

    @Test func digestSelectsTheWeeksData() {
        let d = digest()
        #expect(d.weekKey == "2026-W41")
        #expect(d.deliveries.map(\.name) == ["Informe"])
        #expect(d.grades.map(\.name) == ["Parcial"])
        #expect(d.blocks.map(\.title) == ["Repasar"])
        #expect(d.cardsDue == 4)
        #expect(!d.isEmpty)
    }

    @Test func markdownListsEverySection() {
        let text = digest().markdown
        #expect(text.contains("# Semana 2026-W41"))
        #expect(text.contains("Informe"))
        #expect(text.contains("Control · Parcial: 18"))
        #expect(text.contains("Repasar"))
        #expect(text.contains("4 tarjetas"))
    }

    @Test func emptyDigestSaysSo() {
        let d = WeeklyDigestBuilder.build(now: caracas("2026-10-07T16:00:00Z"), activities: [], isOpen: { _ in true },
                                          grades: [], studyBlocks: [], cardsDue: 0)
        #expect(d.isEmpty)
        #expect(d.markdown.contains("Sin entregas pendientes"))
        #expect(d.markdown.contains("Sin notas nuevas"))
    }

    @Test func promptEmbedsTheDataAndTheOutputFile() {
        let prompt = WeeklySummaryPrompt.make(digest: digest(), outputFile: "2026-W41.md")
        #expect(prompt.contains("`2026-W41.md`"))
        #expect(prompt.contains("Informe"))
    }
}
