import Testing
import Foundation
@testable import Catedra

struct LaunchSyncPolicyTests {
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    func decide(mode: LaunchSyncMode = .full, onboarding: Bool = true, credentials: Bool = true, python: Bool = true,
                last: Date? = nil, minutes: Int = 30, running: Bool = false, disabled: Bool = false) -> LaunchSyncPolicy.Decision {
        LaunchSyncPolicy.decide(mode: mode, onboardingCompleted: onboarding, hasCredentials: credentials, hasPython: python,
                                lastSuccess: last, now: now, minIntervalMinutes: minutes, isSyncRunning: running,
                                disabledByEnvironment: disabled)
    }

    @Test func startsWithFilesInFullMode() { #expect(decide() == .start(includeFiles: true)) }
    @Test func startsWithoutFilesInDataOnlyMode() { #expect(decide(mode: .dataOnly) == .start(includeFiles: false)) }
    @Test func offModeSkips() { #expect(decide(mode: .off) == .skip(.modeOff)) }
    @Test func skipsBeforeOnboardingIsCompleted() { #expect(decide(onboarding: false) == .skip(.onboardingIncomplete)) }
    @Test func skipsWithoutCredentials() { #expect(decide(credentials: false) == .skip(.noCredentials)) }
    @Test func skipsWithoutPython() { #expect(decide(python: false) == .skip(.noPython)) }
    @Test func skipsWhileASyncRuns() { #expect(decide(running: true) == .skip(.syncInProgress)) }
    @Test func environmentOverrideWins() { #expect(decide(running: true, disabled: true) == .skip(.disabledByEnvironment)) }

    @Test func throttlesRecentSuccess() {
        #expect(decide(last: now.addingTimeInterval(-10 * 60)) == .skip(.throttled))
        #expect(decide(last: now.addingTimeInterval(-30 * 60)) == .start(includeFiles: true))
        #expect(decide(last: now.addingTimeInterval(-31 * 60)) == .start(includeFiles: true))
    }

    @Test func zeroIntervalNeverThrottles() {
        #expect(decide(last: now.addingTimeInterval(-5), minutes: 0) == .start(includeFiles: true))
    }

    @Test func aFutureTimestampDoesNotBlockForever() {
        #expect(decide(last: now.addingTimeInterval(3600)) == .start(includeFiles: true))
    }

    @Test func modeRawValuesAreStable() {
        #expect(LaunchSyncMode(rawValue: "full") == .full)
        #expect(LaunchSyncMode(rawValue: "dataOnly") == .dataOnly)
        #expect(LaunchSyncMode(rawValue: "off") == .off)
    }
}

struct SyncSummaryTests {
    func act(_ n: String) -> Activity { makeActivity(name: n, folder: "c/\(n)") }

    @Test func emptyDiffReadsNoChanges() { #expect(SyncSummary.text(for: ActivityDiff()) == "Sin cambios") }

    @Test func joinsCountsWithMiddleDot() {
        var diff = ActivityDiff()
        diff.added = [act("a"), act("b")]
        diff.dueChanges = [Change(activity: act("a"), oldValue: nil, newValue: Date())]
        #expect(SyncSummary.text(for: diff) == "2 actividades nuevas · 1 fecha cambió")
    }

    @Test func singularAndPluralForms() {
        var one = ActivityDiff()
        one.added = [act("a")]; one.removed = [act("r")]
        one.statusChanges = [Change(activity: act("s"), oldValue: "x", newValue: "y")]
        #expect(SyncSummary.text(for: one) == "1 actividad nueva · 1 actividad eliminada · 1 estado cambió")
        var many = ActivityDiff()
        many.dueChanges = [Change(activity: act("a"), oldValue: nil, newValue: nil), Change(activity: act("b"), oldValue: nil, newValue: nil)]
        many.statusChanges = many.dueChanges.map { Change(activity: $0.activity, oldValue: "x", newValue: "y") }
        many.removed = [act("r"), act("q")]
        #expect(SyncSummary.text(for: many) == "2 actividades eliminadas · 2 fechas cambiaron · 2 estados cambiaron")
    }

    @Test func onlyNewActivitiesAndDueChangesAreNotable() {
        var diff = ActivityDiff()
        diff.statusChanges = [Change(activity: act("s"), oldValue: "x", newValue: "y")]
        diff.removed = [act("r")]
        #expect(!SyncSummary.isNotable(diff))
        diff.added = [act("a")]
        #expect(SyncSummary.isNotable(diff))
        var due = ActivityDiff()
        due.dueChanges = [Change(activity: act("a"), oldValue: nil, newValue: Date())]
        #expect(SyncSummary.isNotable(due))
    }

    @Test func failureMessages() {
        #expect(SyncSummary.failure(for: .success(ActivityDiff())) == nil)
        #expect(SyncSummary.failure(for: .failed(exitCode: -15)) == nil)
        let login = SyncSummary.failure(for: .loginFailed("x"))
        #expect(login?.needsSettings == true)
        #expect(login?.text.contains("Ajustes") == true)
        #expect(SyncSummary.failure(for: .failed(exitCode: 1))?.needsSettings == false)
        #expect(SyncSummary.failure(for: .missingPython)?.needsSettings == true)
    }
}
