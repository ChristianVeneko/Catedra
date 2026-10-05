import Testing
import Foundation
@testable import Catedra

struct FocusTimerTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let settings = FocusSettings(focusMinutes: 25, breakMinutes: 5)

    func min(_ m: Double) -> TimeInterval { m * 60 }

    @Test func runsFocusThenRestThenStops() {
        var timer = FocusTimer()
        timer.start(activityID: "a", now: t0, settings: settings)
        #expect(timer.phase == .focus)
        #expect(timer.remaining(now: t0 + min(10)) == min(15))
        #expect(timer.advance(now: t0 + min(24.9)).isEmpty)

        let toRest = timer.advance(now: t0 + min(25))
        #expect(toRest.enteredRest)
        #expect(toRest.sessions.count == 1)
        #expect(toRest.sessions[0].minutes == 25)
        #expect(toRest.sessions[0].end == t0 + min(25))
        #expect(timer.phase == .rest)
        #expect(timer.remaining(now: t0 + min(27)) == min(3))

        let done = timer.advance(now: t0 + min(30))
        #expect(done.finishedRest)
        #expect(!timer.isRunning)
    }

    @Test func lateTickLogsAtTheScheduledEndNotAtNow() {
        var timer = FocusTimer()
        timer.start(activityID: "a", now: t0, settings: settings)
        // Machine slept for two hours: focus ended at +25 min, rest at +30 min.
        let result = timer.advance(now: t0 + min(120))
        #expect(result.sessions.map(\.minutes) == [25])
        #expect(result.sessions[0].end == t0 + min(25))
        #expect(result.enteredRest && result.finishedRest)
        #expect(!timer.isRunning)
    }

    @Test func stopLogsPartialFocusOfAtLeastOneMinute() throws {
        var timer = FocusTimer()
        timer.start(activityID: "a", now: t0, settings: settings)
        let stopped = timer.stop(now: t0 + min(12.4))
        let session = try #require(stopped)
        #expect(session.minutes == 12)
        #expect(session.activityID == "a")
        #expect(!timer.isRunning)
    }

    @Test func stopUnderAMinuteOrDuringRestLogsNothing() {
        var timer = FocusTimer()
        timer.start(activityID: "a", now: t0, settings: settings)
        #expect(timer.stop(now: t0 + 20) == nil)
        timer.start(activityID: "a", now: t0, settings: settings)
        _ = timer.advance(now: t0 + min(26))
        #expect(timer.phase == .rest)
        #expect(timer.stop(now: t0 + min(27)) == nil)
    }

    @Test func startingAnotherActivityClosesTheCurrentOne() throws {
        var timer = FocusTimer()
        timer.start(activityID: "a", now: t0, settings: settings)
        let previous = timer.start(activityID: "b", now: t0 + min(10), settings: settings)
        let closed = try #require(previous)
        #expect(closed.activityID == "a")
        #expect(closed.minutes == 10)
        #expect(timer.activityID == "b")
    }

    @Test func clockGoingBackwardsNeverLogsNegativeTime() {
        var timer = FocusTimer()
        timer.start(activityID: "a", now: t0, settings: settings)
        #expect(timer.stop(now: t0 - 600) == nil)
    }

    @Test func settingsAreClamped() {
        let clamped = FocusSettings(focusMinutes: 0, breakMinutes: 500).clamped
        #expect(clamped.focusMinutes == 1)
        #expect(clamped.breakMinutes == 60)
    }

    @Test func aggregationByActivityAndWeek() {
        let a = FocusSession(activityID: "a", start: t0, end: t0 + min(25))
        let b = FocusSession(activityID: "a", start: t0 + 3 * 86400, end: t0 + 3 * 86400 + min(10))
        let c = FocusSession(activityID: "b", start: t0 + 8 * 86400, end: t0 + 8 * 86400 + min(30))
        let all = [a, b, c]
        #expect(FocusAggregation.totalMinutes(all, activityID: "a") == 35)
        let week = DateInterval(start: t0, duration: 7 * 86400)
        #expect(FocusAggregation.minutes(all, in: week) == 35)
        #expect(FocusAggregation.minutesByActivity(all) == ["a": 35, "b": 30])
        #expect(FocusAggregation.minutesByActivity(all, in: week) == ["a": 35])
    }

    @Test func formatting() {
        #expect(FocusAggregation.text(minutes: 45) == "45 min")
        #expect(FocusAggregation.text(minutes: 60) == "1 h")
        #expect(FocusAggregation.text(minutes: 85) == "1 h 25 min")
        #expect(FocusAggregation.clock(725) == "12:05")
        #expect(FocusAggregation.clock(0.2) == "0:01")
        #expect(FocusAggregation.weekComparisonText(actualMinutes: 70, plannedHours: 3) == "1 h 10 min de enfoque real · 3 h planificadas")
        #expect(FocusAggregation.weekComparisonText(actualMinutes: 30, plannedHours: 0) == "30 min de enfoque")
        #expect(FocusAggregation.weekComparisonText(actualMinutes: 0, plannedHours: 0) == nil)
    }
}
