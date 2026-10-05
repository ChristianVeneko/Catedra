import Foundation

/// Per-course choice for the new-activity autopilot.
enum AutopilotOverride: String, Codable, CaseIterable, Sendable {
    case inherit, on, off

    var label: String {
        switch self {
        case .inherit: "Usar el ajuste general"
        case .on: "Activado"
        case .off: "Desactivado"
        }
    }
}

enum PlanStatus: String, Codable, Sendable { case queued, running, ready, failed }

struct PlanEntry: Codable, Equatable, Sendable {
    var status: PlanStatus
    var updatedAt: Date
}

struct AutopilotLimits: Equatable, Sendable {
    static let defaultDailyCap = 3
    var maxConcurrent = 1
    var dailyCap = AutopilotLimits.defaultDailyCap
}

/// App-owned autopilot state. `seenIDs == nil` means no baseline has been taken yet.
struct AutopilotState: Codable, Equatable, Sendable {
    var seenIDs: [String]?
    var plans: [String: PlanEntry] = [:]
    /// Start dates of the runs launched by the autopilot (for the daily cap).
    var launches: [Date] = []
}

/// Pure decisions of the autopilot: which activities are new, which may get a plan, and when to launch.
enum AutopilotRules {
    static let recipeID = "work-plan"

    static func isEnabled(global: Bool, override: AutopilotOverride?) -> Bool {
        switch override ?? .inherit {
        case .inherit: global
        case .on: true
        case .off: false
        }
    }

    /// The "Plan de trabajo" recipe applies to assignments only (quizzes and exams are never touched), and nothing is
    /// planned for work already delivered or overdue.
    static func isEligible(_ activity: Activity, state: ActivityState) -> Bool {
        guard let recipe = RecipeCatalog.recipe(id: recipeID), recipe.applies(to: .activity(activity)) else { return false }
        return state == .pending || state == .inProgress || state == .upcoming
    }

    /// Marks every activity as seen and queues the new, eligible ones. Without a baseline (first run) it only records.
    static func detectNew(state: AutopilotState, activities: [Activity], isEnabled: (Activity) -> Bool,
                          stateOf: (Activity) -> ActivityState, now: Date) -> AutopilotState {
        var state = state
        guard !activities.isEmpty else { return state } // a failed read must not reset the baseline
        guard let seenList = state.seenIDs else {
            state.seenIDs = activities.map(\.id).sorted()
            return state
        }
        var seen = Set(seenList)
        for activity in activities where seen.insert(activity.id).inserted {
            guard isEnabled(activity), isEligible(activity, state: stateOf(activity)) else { continue }
            state.plans[activity.id] = PlanEntry(status: .queued, updatedAt: now)
        }
        state.seenIDs = seen.sorted()
        return state
    }

    static func launchesToday(_ state: AutopilotState, now: Date, calendar: Calendar) -> Int {
        state.launches.filter { calendar.isDate($0, inSameDayAs: now) }.count
    }

    /// Queued activity ids to start now, oldest first, within the concurrency and daily limits.
    static func nextToLaunch(_ state: AutopilotState, now: Date, limits: AutopilotLimits, calendar: Calendar) -> [String] {
        let running = state.plans.values.filter { $0.status == .running }.count
        let slots = min(limits.maxConcurrent - running, limits.dailyCap - launchesToday(state, now: now, calendar: calendar))
        guard slots > 0 else { return [] }
        let queued = state.plans.filter { $0.value.status == .queued }
            .sorted { ($0.value.updatedAt, $0.key) < ($1.value.updatedAt, $1.key) }
        return queued.prefix(slots).map(\.key)
    }

    static func markRunning(_ state: AutopilotState, id: String, now: Date) -> AutopilotState {
        var state = state
        state.plans[id] = PlanEntry(status: .running, updatedAt: now)
        state.launches.append(now)
        state.launches = state.launches.filter { now.timeIntervalSince($0) < 7 * 86400 }
        return state
    }

    static func finish(_ state: AutopilotState, id: String, succeeded: Bool, now: Date) -> AutopilotState {
        var state = state
        state.plans[id] = PlanEntry(status: succeeded ? .ready : .failed, updatedAt: now)
        return state
    }

    static func discard(_ state: AutopilotState, id: String) -> AutopilotState {
        var state = state
        state.plans[id] = nil
        return state
    }

    /// Entries left `running` by a previous launch can no longer finish: they are failed on startup.
    static func recoverInterrupted(_ state: AutopilotState, now: Date) -> AutopilotState {
        var state = state
        for (id, entry) in state.plans where entry.status == .running { state.plans[id] = PlanEntry(status: .failed, updatedAt: now) }
        return state
    }
}
