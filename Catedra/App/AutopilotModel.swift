import Foundation
import Observation

/// Launches the "Plan de trabajo" recipe in the background for activities that appear after a sync.
@Observable @MainActor
final class AutopilotModel {
    private(set) var state = AutopilotState()

    private let store: any StateStoring<AutopilotState>
    private let calendar: Calendar
    /// Settings, resolved on demand so changes apply to the next sync.
    var isEnabled: @MainActor (Activity) -> Bool = { _ in false }
    var limits: @MainActor () -> AutopilotLimits = { AutopilotLimits() }
    var stateOf: @MainActor (Activity) -> ActivityState = { _ in .pending }
    var activityLookup: @MainActor (String) -> Activity? = { _ in nil }
    /// Starts the recipe for an activity; returns the run id, or nil when the agent could not start.
    var launch: @MainActor (Activity, Recipe) -> UUID? = { _, _ in nil }
    @ObservationIgnored private var runs: [UUID: String] = [:]

    init(store: any StateStoring<AutopilotState>, calendar: Calendar = .current) {
        self.store = store
        self.calendar = calendar
    }

    func load(now: Date = .now) {
        state = AutopilotRules.recoverInterrupted(store.load() ?? AutopilotState(), now: now)
        persist()
    }

    func planStatus(for activityID: String) -> PlanStatus? { state.plans[activityID]?.status }

    func process(activities: [Activity], now: Date = .now) {
        state = AutopilotRules.detectNew(state: state, activities: activities, isEnabled: isEnabled, stateOf: stateOf, now: now)
        persist()
        pump(now: now)
    }

    /// Starts queued plans within the concurrency and daily limits.
    func pump(now: Date = .now) {
        for id in AutopilotRules.nextToLaunch(state, now: now, limits: limits(), calendar: calendar) {
            guard let activity = activityLookup(id), isEnabled(activity), AutopilotRules.isEligible(activity, state: stateOf(activity)),
                  let recipe = RecipeCatalog.recipe(id: AutopilotRules.recipeID) else {
                state = AutopilotRules.discard(state, id: id)
                continue
            }
            if let runID = launch(activity, recipe) {
                runs[runID] = id
                state = AutopilotRules.markRunning(state, id: id, now: now)
            } else {
                state = AutopilotRules.finish(state, id: id, succeeded: false, now: now)
            }
        }
        persist()
    }

    func runFinished(runID: UUID, succeeded: Bool, now: Date = .now) {
        guard let id = runs.removeValue(forKey: runID) else { return }
        state = AutopilotRules.finish(state, id: id, succeeded: succeeded, now: now)
        persist()
        pump(now: now)
    }

    private func persist() { try? store.save(state) }
}
