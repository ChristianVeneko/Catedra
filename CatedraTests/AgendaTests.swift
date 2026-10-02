import Testing
import Foundation
@testable import Catedra

struct AgendaTests {
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Caracas")!
        return c
    }
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    func state(_ a: Activity) -> ActivityState { ActivityState.derive(from: a, hasUserWork: false, now: now) }

    @Test func buildsHeroTimelineLaterAndUndated() {
        let h = makeActivity(name: "hero", due: now.addingTimeInterval(3600), folder: "f/hero")
        let d2 = makeActivity(name: "dia2", due: now.addingTimeInterval(2 * 86400), folder: "f/d2")
        let far = makeActivity(name: "lejos", due: now.addingTimeInterval(40 * 86400), folder: "f/far")
        let none = makeActivity(name: "sin", due: nil, folder: "f/none")
        let late = makeActivity(name: "tarde", due: now.addingTimeInterval(-3600), folder: "f/late")
        let done = makeActivity(name: "hecha", due: now.addingTimeInterval(7200), status: "Entregado", folder: "f/done")
        let agenda = Agenda.build(activities: [far, none, d2, late, h, done], stateOf: state, now: now, calendar: calendar)
        #expect(agenda.hero?.name == "hero")
        #expect(agenda.days.flatMap(\.activities).map(\.name) == ["dia2"])
        #expect(agenda.later.map(\.name) == ["lejos"])
        #expect(agenda.undated.map(\.name) == ["sin"])
        #expect(agenda.overdue.map(\.name) == ["tarde"])
    }

    @Test func groupsSameDayTogether() {
        let a = makeActivity(name: "a", due: now.addingTimeInterval(2 * 86400), folder: "f/a")
        let b = makeActivity(name: "b", due: now.addingTimeInterval(2 * 86400 + 60), folder: "f/b")
        let hero = makeActivity(name: "h", due: now.addingTimeInterval(60), folder: "f/h")
        let agenda = Agenda.build(activities: [a, b, hero], stateOf: state, now: now, calendar: calendar)
        #expect(agenda.days.count == 1)
        #expect(agenda.days[0].activities.map(\.name) == ["a", "b"])
    }
}
