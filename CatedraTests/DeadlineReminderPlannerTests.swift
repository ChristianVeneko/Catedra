import Testing
import Foundation
@testable import Catedra

struct DeadlineReminderPlannerTests {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    let hour: TimeInterval = 3600

    func plan(_ activities: [Activity], offsets: [Int] = [48, 24, 3], limit: Int = 60,
              state: ActivityState? = nil) -> [DeadlineReminder] {
        DeadlineReminderPlanner.plan(
            activities: activities,
            stateOf: { a in state ?? ActivityState.derive(from: a, hasUserWork: false, now: now) },
            now: now, offsetsHours: offsets, limit: limit, formatDue: { _ in "DUE" })
    }

    @Test func plansOneReminderPerOffsetAtTheRightTime() {
        let due = now.addingTimeInterval(100 * hour)
        let result = plan([makeActivity(name: "Parcial", due: due)])
        #expect(result.map(\.offsetHours) == [48, 24, 3])
        #expect(result.map(\.fireDate) == [due.addingTimeInterval(-48 * hour), due.addingTimeInterval(-24 * hour), due.addingTimeInterval(-3 * hour)].sorted())
    }

    @Test func ordersByFireDateRegardlessOfOffsetOrder() {
        let due = now.addingTimeInterval(100 * hour)
        let result = plan([makeActivity(due: due)], offsets: [3, 48, 24])
        #expect(result.map(\.offsetHours) == [48, 24, 3])
    }

    @Test func skipsFireDatesInThePast() {
        let result = plan([makeActivity(due: now.addingTimeInterval(30 * hour))])
        #expect(result.map(\.offsetHours) == [24, 3])
        let late = plan([makeActivity(due: now.addingTimeInterval(2 * hour))])
        #expect(late.isEmpty)
    }

    @Test func skipsSubmittedOverdueAndUndatedActivities() {
        let due = now.addingTimeInterval(100 * hour)
        let submitted = makeActivity(name: "a", due: due, status: "Entregado", folder: "c/a")
        let graded = makeActivity(name: "g", due: due, grade: "18", folder: "c/g")
        let undated = makeActivity(name: "u", due: nil, folder: "c/u")
        let overdue = makeActivity(name: "o", due: now.addingTimeInterval(-hour), folder: "c/o")
        #expect(plan([submitted, graded, undated, overdue]).isEmpty)
    }

    @Test func keepsUpcomingActivitiesThatHaveADueDate() {
        let upcoming = makeActivity(kind: .examen, name: "Parcial", due: now.addingTimeInterval(100 * hour), status: "Próximo")
        #expect(plan([upcoming]).count == 3)
    }

    @Test func idsAreStableAndDependOnActivityOffsetAndDue() {
        let due = now.addingTimeInterval(100 * hour)
        let a = makeActivity(name: "a", due: due, folder: "c/a")
        let first = plan([a]), second = plan([a])
        #expect(first.map(\.id) == second.map(\.id))
        #expect(Set(first.map(\.id)).count == 3)
        #expect(first.allSatisfy { $0.id.hasPrefix(DeadlineReminderPlanner.idPrefix) })
        let moved = makeActivity(name: "a", due: due.addingTimeInterval(hour), folder: "c/a")
        #expect(Set(plan([moved]).map(\.id)).isDisjoint(with: first.map(\.id)))
    }

    @Test func buildsTitleAndBody() throws {
        let a = makeActivity(course: "Teoria de Control II", kind: .examen, name: "Parcial 1", due: now.addingTimeInterval(100 * hour))
        let reminder = try #require(plan([a]).first { $0.offsetHours == 24 })
        #expect(reminder.title == "Vence en 24 h: Parcial 1")
        #expect(reminder.body == "Teoria de Control II · Examen · DUE")
        #expect(reminder.activityID == a.id)
    }

    @Test func formatsDueInCaracasByDefault() throws {
        let due = Date(timeIntervalSince1970: 1_790_942_400).addingTimeInterval(200 * hour)
        let a = makeActivity(due: due)
        let reminder = try #require(DeadlineReminderPlanner.plan(
            activities: [a], stateOf: { _ in .pending }, now: due.addingTimeInterval(-100 * hour), offsetsHours: [24]).first)
        #expect(reminder.body.hasSuffix(Formatters.due(due)))
    }

    @Test func ignoresInvalidAndDuplicateOffsets() {
        let due = now.addingTimeInterval(100 * hour)
        #expect(plan([makeActivity(due: due)], offsets: [24, 24, 0, -5]).map(\.offsetHours) == [24])
    }

    @Test func capsToNearestFirst() {
        let activities = (1...30).map { i in
            makeActivity(name: "a\(i)", due: now.addingTimeInterval(Double(i) * 60 * hour), folder: "c/a\(i)")
        }
        let all = plan(activities, limit: 1000)
        let capped = plan(activities, limit: 10)
        #expect(capped.count == 10)
        #expect(capped.map(\.id) == Array(all.prefix(10)).map(\.id))
        #expect(capped == capped.sorted { $0.fireDate < $1.fireDate })
        #expect(DeadlineReminderPlanner.maxPending == 60)
    }

    // MARK: diff

    @Test func diffAddsMissingAndRemovesStaleOwnedIdsOnly() {
        let due = now.addingTimeInterval(100 * hour)
        let planned = plan([makeActivity(due: due)])
        let existing = planned[0].id
        let stale = DeadlineReminderPlanner.idPrefix + "old"
        let foreign = "other.request"
        let diff = DeadlineReminderPlanner.diff(planned: planned, pendingIDs: [existing, stale, foreign])
        #expect(diff.toAdd.map(\.id) == planned.dropFirst().map(\.id))
        #expect(diff.toRemove == [stale])
    }

    @Test func diffIsEmptyWhenAlreadyInSync() {
        let planned = plan([makeActivity(due: now.addingTimeInterval(100 * hour))])
        let diff = DeadlineReminderPlanner.diff(planned: planned, pendingIDs: Set(planned.map(\.id)))
        #expect(diff.toAdd.isEmpty && diff.toRemove.isEmpty)
    }

    // MARK: preferences

    @Test func preferencesProduceOffsets() {
        var prefs = ReminderPreferences(); prefs.enabled = true
        #expect(prefs.offsetsHours == [48, 24, 3])
        prefs.at24h = false
        prefs.customEnabled = true
        prefs.customHours = 6
        #expect(prefs.offsetsHours == [48, 6, 3])
        prefs.enabled = false
        #expect(prefs.offsetsHours.isEmpty)
    }
}
