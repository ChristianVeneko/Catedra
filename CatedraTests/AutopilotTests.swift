import Testing
import Foundation
@testable import Catedra

struct AutopilotTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = .gmt; return c }

    func task(_ n: String, kind: ActivityKind = .tarea) -> Activity {
        makeActivity(kind: kind, name: n, folder: "08 - X/actividades/\(n)")
    }

    func detect(_ state: AutopilotState, _ list: [Activity], enabled: Bool = true,
                stateOf: ActivityState = .pending) -> AutopilotState {
        AutopilotRules.detectNew(state: state, activities: list, isEnabled: { _ in enabled }, stateOf: { _ in stateOf }, now: t0)
    }

    @Test func firstSyncOnlyTakesTheBaseline() {
        let state = detect(AutopilotState(), [task("a"), task("b")])
        #expect(state.plans.isEmpty)
        #expect(state.seenIDs?.count == 2)
    }

    @Test func newActivityAfterBaselineIsQueued() {
        var state = detect(AutopilotState(), [task("a")])
        state = detect(state, [task("a"), task("b")])
        #expect(Array(state.plans.keys) == [task("b").id])
        #expect(state.plans[task("b").id]?.status == .queued)
        // Seen now: the next sync does not queue it again.
        state.plans = [:]
        #expect(detect(state, [task("a"), task("b")]).plans.isEmpty)
    }

    @Test func disabledOrIneligibleActivitiesAreSeenButNotQueued() {
        var state = detect(AutopilotState(), [task("a")])
        let off = detect(state, [task("a"), task("b")], enabled: false)
        #expect(off.plans.isEmpty)
        #expect(off.seenIDs?.contains(task("b").id) == true)
        state = detect(state, [task("a"), task("quiz", kind: .cuestionario), task("exam", kind: .examen)])
        #expect(state.plans.isEmpty)
        #expect(detect(state, [task("a"), task("late")], stateOf: .overdue).plans.isEmpty)
        #expect(detect(state, [task("a"), task("sent")], stateOf: .submitted).plans.isEmpty)
    }

    @Test func emptyReadDoesNotResetTheBaseline() {
        let state = detect(AutopilotState(), [task("a")])
        #expect(detect(state, []) == state)
        #expect(detect(AutopilotState(), []).seenIDs == nil)
    }

    @Test func overridesResolveAgainstTheGlobalSetting() {
        #expect(!AutopilotRules.isEnabled(global: false, override: nil))
        #expect(AutopilotRules.isEnabled(global: true, override: .inherit))
        #expect(AutopilotRules.isEnabled(global: false, override: .on))
        #expect(!AutopilotRules.isEnabled(global: true, override: .off))
    }

    func queued(_ ids: [String]) -> AutopilotState {
        var state = AutopilotState(seenIDs: [])
        for (i, id) in ids.enumerated() { state.plans[id] = PlanEntry(status: .queued, updatedAt: t0.addingTimeInterval(Double(i))) }
        return state
    }

    @Test func launchesOneAtATimeOldestFirst() {
        let state = queued(["b", "a", "c"])
        let limits = AutopilotLimits(maxConcurrent: 1, dailyCap: 3)
        #expect(AutopilotRules.nextToLaunch(state, now: t0, limits: limits, calendar: calendar) == ["b"])
        let running = AutopilotRules.markRunning(state, id: "b", now: t0)
        #expect(AutopilotRules.nextToLaunch(running, now: t0, limits: limits, calendar: calendar).isEmpty)
        let done = AutopilotRules.finish(running, id: "b", succeeded: true, now: t0)
        #expect(done.plans["b"]?.status == .ready)
        #expect(AutopilotRules.nextToLaunch(done, now: t0, limits: limits, calendar: calendar) == ["a"])
    }

    @Test func dailyCapStopsLaunchesUntilTheNextDay() {
        var state = queued(["a", "b", "c", "d"])
        let limits = AutopilotLimits(maxConcurrent: 1, dailyCap: 2)
        for id in ["a", "b"] {
            state = AutopilotRules.markRunning(state, id: id, now: t0)
            state = AutopilotRules.finish(state, id: id, succeeded: true, now: t0)
        }
        #expect(AutopilotRules.launchesToday(state, now: t0, calendar: calendar) == 2)
        #expect(AutopilotRules.nextToLaunch(state, now: t0, limits: limits, calendar: calendar).isEmpty)
        #expect(AutopilotRules.nextToLaunch(state, now: t0.addingTimeInterval(2 * 86400), limits: limits, calendar: calendar) == ["c"])
    }

    @Test func interruptedRunsAreFailedOnStartup() {
        let state = AutopilotRules.markRunning(queued(["a"]), id: "a", now: t0)
        #expect(AutopilotRules.recoverInterrupted(state, now: t0).plans["a"]?.status == .failed)
    }

    @Test func workPlanRecipeNeverAppliesToEvaluations() {
        let recipe = RecipeCatalog.recipe(id: AutopilotRules.recipeID)
        #expect(recipe?.applies(to: .activity(task("q", kind: .cuestionario))) == false)
        #expect(recipe?.applies(to: .activity(task("t"))) == true)
    }
}

@MainActor
struct AutopilotModelTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func activity(_ n: String) -> Activity { makeActivity(name: n, folder: "08 - X/actividades/\(n)") }

    func makeModel(launched: @escaping (Activity) -> Void) -> AutopilotModel {
        let model = AutopilotModel(store: MemoryStateStore<AutopilotState>())
        model.isEnabled = { _ in true }
        model.activityLookup = { id in [self.activity("a"), self.activity("b"), self.activity("c")].first { $0.id == id } }
        model.launch = { activity, _ in launched(activity); return UUID() }
        return model
    }

    @Test func baselineThenNewActivityLaunchesOnePlanAtATime() {
        var launched: [String] = []
        let model = makeModel { launched.append($0.name) }
        model.process(activities: [activity("a")], now: t0)
        #expect(launched.isEmpty)
        model.process(activities: [activity("a"), activity("b"), activity("c")], now: t0)
        #expect(launched.count == 1)
        #expect(model.planStatus(for: activity(launched[0]).id) == .running)
    }

    @Test func finishingARunReleasesTheNextAndMarksPlanReady() {
        var runIDs: [UUID] = []
        var launched: [String] = []
        let model = AutopilotModel(store: MemoryStateStore<AutopilotState>())
        model.isEnabled = { _ in true }
        model.activityLookup = { id in [self.activity("a"), self.activity("b"), self.activity("c")].first { $0.id == id } }
        model.launch = { a, _ in let id = UUID(); runIDs.append(id); launched.append(a.name); return id }
        model.process(activities: [activity("a")], now: t0)
        model.process(activities: [activity("a"), activity("b"), activity("c")], now: t0)
        let first = launched[0]
        model.runFinished(runID: runIDs[0], succeeded: true, now: t0)
        #expect(model.planStatus(for: activity(first).id) == .ready)
        #expect(launched.count == 2)
    }

    @Test func aFailedStartIsMarkedFailedAndDoesNotBlockTheQueue() {
        let model = AutopilotModel(store: MemoryStateStore<AutopilotState>())
        model.isEnabled = { _ in true }
        model.activityLookup = { _ in self.activity("b") }
        model.launch = { _, _ in nil }
        model.process(activities: [activity("a")], now: t0)
        model.process(activities: [activity("a"), activity("b")], now: t0)
        #expect(model.planStatus(for: activity("b").id) == .failed)
    }

    @Test func disablingBeforeLaunchDiscardsTheQueuedPlan() {
        var enabled = true
        var launched = 0
        let model = AutopilotModel(store: MemoryStateStore<AutopilotState>())
        model.isEnabled = { _ in enabled }
        model.activityLookup = { _ in self.activity("b") }
        model.launch = { _, _ in launched += 1; return UUID() }
        model.process(activities: [activity("a")], now: t0)
        model.limits = { AutopilotLimits(maxConcurrent: 0, dailyCap: 3) } // nothing may start yet
        model.process(activities: [activity("a"), activity("b")], now: t0)
        #expect(model.planStatus(for: activity("b").id) == .queued)
        enabled = false
        model.limits = { AutopilotLimits() }
        model.pump(now: t0)
        #expect(launched == 0)
        #expect(model.planStatus(for: activity("b").id) == nil)
    }
}
