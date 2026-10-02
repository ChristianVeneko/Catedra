import Testing
import Foundation
@testable import Catedra

struct MenuBarLabelTests {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    let hour: TimeInterval = 3600

    @Test func noDeadlineShowsOnlyTheIcon() {
        let label = MenuBarLabel.make(nextDue: nil, now: now, showsCountdown: true)
        #expect(label.text == nil)
        #expect(label.tone == .normal)
    }

    @Test func formatsCountdownText() {
        let label = MenuBarLabel.make(nextDue: now.addingTimeInterval(31 * hour), now: now, showsCountdown: true)
        #expect(label.text == "1 d 7 h")
    }

    @Test func hidingTheTextKeepsTheToneAsAHint() {
        let label = MenuBarLabel.make(nextDue: now.addingTimeInterval(2 * hour), now: now, showsCountdown: false)
        #expect(label.text == nil)
        #expect(label.tone == .critical)
    }

    @Test(arguments: [
        (100.0, MenuBarLabel.Tone.normal), (24.0, .normal), (23.9, .warning),
        (3.0, .warning), (2.99, .critical), (0.5, .critical),
    ])
    func toneThresholds(hours: Double, expected: MenuBarLabel.Tone) {
        let label = MenuBarLabel.make(nextDue: now.addingTimeInterval(hours * hour), now: now, showsCountdown: true)
        #expect(label.tone == expected)
    }

    @Test func pastDeadlinesAreNotShown() {
        let label = MenuBarLabel.make(nextDue: now.addingTimeInterval(-hour), now: now, showsCountdown: true)
        #expect(label.text == nil)
    }

    @Test func upcomingListsOpenFutureActivitiesNearestFirst() {
        let a = makeActivity(name: "a", due: now.addingTimeInterval(5 * hour), folder: "c/a")
        let b = makeActivity(name: "b", due: now.addingTimeInterval(2 * hour), folder: "c/b")
        let done = makeActivity(name: "d", due: now.addingTimeInterval(hour), status: "Entregado", folder: "c/d")
        let late = makeActivity(name: "l", due: now.addingTimeInterval(-hour), folder: "c/l")
        let none = makeActivity(name: "n", due: nil, folder: "c/n")
        let result = UpcomingActivities.next([a, b, done, late, none],
                                             stateOf: { ActivityState.derive(from: $0, hasUserWork: false, now: now) },
                                             now: now, limit: 5)
        #expect(result.map(\.name) == ["b", "a"])
        #expect(UpcomingActivities.next([a, b], stateOf: { _ in .pending }, now: now, limit: 1).map(\.name) == ["b"])
    }
}
