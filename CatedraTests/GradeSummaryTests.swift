import Testing
import Foundation
@testable import Catedra

enum GradeFixtures {
    static func item(_ name: String, raw: Double? = nil, max: Double? = 20, type: String = "mod", module: String = "assign",
                     cmid: Int? = nil, weight: Double? = nil, graded: Int? = nil, feedback: String = "") -> GradeItem {
        GradeItem(name: name, itemType: type, itemModule: module, cmid: cmid, gradeRaw: raw, gradeFormatted: raw.map { "\($0)" } ?? "-",
                  gradeMin: 0, gradeMax: max, weight: weight, percentage: "", feedback: feedback, submittedAt: nil,
                  gradedAt: graded.map { Date(timeIntervalSince1970: TimeInterval($0)) })
    }

    static func line(_ name: String, earned: Double? = nil, max: Double = 20, makeup: Bool = false, extra: Bool = false,
                     excluded: Bool = false, at: Int? = nil) -> GradeLine {
        GradeLine(id: "k#\(name)", courseKey: "k", name: name, module: "assign", cmid: nil, earned: earned, max: max,
                  gradedAt: at.map { Date(timeIntervalSince1970: TimeInterval($0)) }, feedback: "", isMakeup: makeup,
                  isExtra: extra, excluded: excluded)
    }
}

struct GradeRulesTests {
    typealias G = GradeFixtures

    @Test func onlyModAndManualItemsAreGradeable() {
        let report = GradeReport(courseId: 1, items: [
            G.item("Parcial", raw: 15, type: "mod"), G.item("Extra manual", raw: 2, type: "manual"),
            G.item("", type: "category"), G.item("", max: 100, type: "course"),
        ], total: nil)
        let lines = GradeRules.lines(report: report, courseKey: "01 - X", excluded: [])
        #expect(lines.map(\.name) == ["Parcial", "Extra manual"])
    }

    @Test func makeupAndExtraDetectionIsAccentAndCaseInsensitive() {
        #expect(GradeRules.isMakeup("Parcial No. 1 Diferido"))
        #expect(GradeRules.isMakeup("EXAMEN SUSTITUTIVO"))
        #expect(!GradeRules.isMakeup("Parcial No. 1"))
        #expect(GradeRules.isExtra("Puntos Extra"))
        #expect(GradeRules.isExtra("Bonus quiz"))
        #expect(!GradeRules.isExtra("Extracurricular"))
    }

    @Test func itemKeyPrefersCmidElseFoldedName() {
        #expect(GradeRules.itemKey(courseKey: "c", item: G.item("A", cmid: 9)) == "c#cmid9")
        #expect(GradeRules.itemKey(courseKey: "c", item: G.item("Ménos Uno")) == "c#menos uno")
    }

    @Test func excludedKeysMarkLines() {
        let report = GradeReport(courseId: 1, items: [G.item("Parcial", cmid: 5)], total: nil)
        let lines = GradeRules.lines(report: report, courseKey: "c", excluded: ["c#cmid5"])
        #expect(lines[0].excluded)
    }

    @Test func missingMaxCountsAsZeroPossible() {
        let report = GradeReport(courseId: 1, items: [G.item("Sin max", raw: 3, max: nil)], total: nil)
        #expect(GradeRules.lines(report: report, courseKey: "c", excluded: [])[0].max == 0)
    }
}

struct GradeSummaryTests {
    typealias G = GradeFixtures

    @Test func sumsGradedAndTotalPoints() {
        let s = GradeCalculator.summary(lines: [
            G.line("P1", earned: 15, max: 20), G.line("P2", earned: 8, max: 10), G.line("P3", max: 20), G.line("P4", max: 50),
        ])
        #expect(s.earned == 23 && s.gradedPossible == 30 && s.totalPossible == 100 && s.remaining == 70)
        #expect(abs((s.currentPercentage ?? 0) - 76.6667) < 0.01)
        #expect(s.accumulatedPercentage == 23)
        #expect(abs((s.projectedPoints ?? 0) - 76.6667) < 0.01)
    }

    @Test func makeupItemsDoNotCountUntilGraded() {
        let ungraded = GradeCalculator.summary(lines: [G.line("P1", earned: 10, max: 20), G.line("P1 Diferido", max: 20, makeup: true)])
        #expect(ungraded.totalPossible == 20)
        let graded = GradeCalculator.summary(lines: [G.line("P1", earned: 10, max: 20), G.line("P1 Diferido", earned: 12, max: 20, makeup: true)])
        #expect(graded.totalPossible == 40 && graded.earned == 22)
    }

    @Test func excludedItemsCountNowhere() {
        let s = GradeCalculator.summary(lines: [G.line("P1", earned: 10, max: 20), G.line("P1b", earned: 20, max: 20, excluded: true),
                                                G.line("P2", max: 20, excluded: true)])
        #expect(s.earned == 10 && s.totalPossible == 20 && s.remaining == 0)
    }

    @Test func extraCreditEarnsButAddsNoPossiblePoints() {
        let s = GradeCalculator.summary(lines: [G.line("P1", earned: 18, max: 20), G.line("Puntos extra", earned: 3, max: 5, extra: true)])
        #expect(s.earned == 21 && s.totalPossible == 20 && s.gradedPossible == 20)
        // grade above its maximum on a normal item: earned in full, possible capped at the maximum
        let over = GradeCalculator.summary(lines: [G.line("Quiz", earned: 22, max: 20)])
        #expect(over.earned == 22 && over.totalPossible == 20)
    }

    @Test func nothingGradedHasNoPercentageAndIsOnTrack() {
        let s = GradeCalculator.summary(lines: [G.line("P1", max: 50), G.line("P2", max: 50)])
        #expect(s.currentPercentage == nil && s.projectedPoints == nil && s.earned == 0)
        #expect(s.status == .onTrack && s.hasData)
    }

    @Test func noGradeableLinesHasNoData() {
        let s = GradeCalculator.summary(lines: [])
        #expect(!s.hasData && s.status == .onTrack && s.currentPercentage == nil)
    }

    @Test func statusPassedWhenTargetReached() {
        let s = GradeCalculator.summary(lines: [G.line("P1", earned: 50, max: 50), G.line("P2", max: 50)])
        #expect(s.status == .passed)
        let need = s.needed(forTargetPercent: 50)
        #expect(need.isMet && need.points == 0 && need.averageFraction == 0)
    }

    @Test func statusAtRiskWhenProjectionIsBelowTarget() {
        let s = GradeCalculator.summary(lines: [G.line("P1", earned: 10, max: 40), G.line("P2", max: 60)])
        #expect(s.status == .atRisk)
        let need = s.needed(forTargetPercent: 50)
        #expect(need.points == 40 && need.isReachable)
        #expect(abs((need.averageFraction ?? 0) - 40.0 / 60.0) < 1e-9)
    }

    @Test func statusOnTrackWhenProjectionMeetsTarget() {
        let s = GradeCalculator.summary(lines: [G.line("P1", earned: 30, max: 40), G.line("P2", max: 60)])
        #expect(s.status == .onTrack)
    }

    @Test func statusUnreachableWhenRemainingCannotCoverTarget() {
        let s = GradeCalculator.summary(lines: [G.line("P1", earned: 5, max: 60), G.line("P2", max: 30)], targetPercent: 50)
        // total 90, target 45, earned 5, remaining 30: even a perfect finish reaches 35
        #expect(s.status == .unreachable)
        let need = s.needed(forTargetPercent: 50)
        #expect(!need.isReachable && (need.averageFraction ?? 0) > 1)
    }

    @Test func nothingRemainingAndBelowTargetIsUnreachableWithNoAverage() {
        let s = GradeCalculator.summary(lines: [G.line("P1", earned: 10, max: 50), G.line("P2", earned: 10, max: 50)])
        #expect(s.status == .unreachable)
        #expect(s.needed(forTargetPercent: 50).averageFraction == nil)
    }

    @Test func targetPercentChangesTargetPoints() {
        let s = GradeCalculator.summary(lines: [G.line("P1", earned: 30, max: 50), G.line("P2", max: 50)], targetPercent: 70)
        #expect(s.targetPoints == 70 && s.status != .passed)
        #expect(s.needed(forTargetPercent: 90).points == 60)
    }

    @Test func realisticSplitSubjectAddsToOneHundred() {
        let theory = [G.line("Parcial 1", earned: 12, max: 15), G.line("Parcial 2", max: 15), G.line("Taller", earned: 10, max: 20)]
        let lab = [G.line("Informe 1", earned: 18, max: 20), G.line("Informe 2", max: 30)]
        let s = GradeCalculator.summary(lines: theory + lab)
        #expect(s.totalPossible == 100 && s.earned == 40 && s.gradedPossible == 55)
    }

    @Test func cumulativeSeriesIsSortedAndSkipsUnusableLines() {
        let points = GradeCalculator.cumulative(lines: [
            G.line("B", earned: 5, max: 10, at: 200), G.line("A", earned: 10, max: 10, at: 100), G.line("C", max: 10),
            G.line("D", earned: 9, max: 10, excluded: true, at: 300), G.line("E", earned: 4, max: 10),
            G.line("Extra", earned: 2, max: 5, extra: true, at: 400),
        ])
        #expect(points.map(\.points) == [10, 15, 17])
        #expect(points.map(\.date) == [100, 200, 400].map { Date(timeIntervalSince1970: TimeInterval($0)) })
    }
}
