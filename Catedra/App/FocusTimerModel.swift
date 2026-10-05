import Foundation
import Observation

/// Owns the focus timer so it survives the window closing; ticks only while a period is running.
@Observable @MainActor
final class FocusTimerModel {
    private(set) var timer = FocusTimer()
    private(set) var sessions: [FocusSession] = []
    /// Updated every second while running; views read it to refresh.
    private(set) var now = Date()
    private(set) var activityName: String?

    private let store: any StateStoring<[FocusSession]>
    private let notifier: AgentNotifying?
    private let settings: @MainActor () -> FocusSettings
    private let clock: @MainActor () -> Date
    @ObservationIgnored private var ticker: Task<Void, Never>?

    init(store: any StateStoring<[FocusSession]>, notifier: AgentNotifying? = nil,
         settings: @escaping @MainActor () -> FocusSettings = { FocusSettings() },
         clock: @escaping @MainActor () -> Date = { .now }) {
        self.store = store
        self.notifier = notifier
        self.settings = settings
        self.clock = clock
    }

    func load() { sessions = store.load() ?? [] }

    var isRunning: Bool { timer.isRunning }
    var phase: FocusTimer.Phase? { timer.phase }
    var activityID: String? { timer.activityID }
    var remaining: TimeInterval? { timer.remaining(now: now) }
    var remainingText: String? { remaining.map(FocusAggregation.clock) }

    func isRunning(activityID id: String) -> Bool { timer.activityID == id }

    func totalMinutes(for activityID: String) -> Int { FocusAggregation.totalMinutes(sessions, activityID: activityID) }

    func minutes(in interval: DateInterval) -> Int { FocusAggregation.minutes(sessions, in: interval) }

    func start(activityID: String, name: String) {
        now = clock()
        if let logged = timer.start(activityID: activityID, now: now, settings: settings()) { record([logged]) }
        activityName = name
        startTicker()
    }

    func stop() {
        now = clock()
        if let logged = timer.stop(now: now) { record([logged]) }
        activityName = nil
        ticker?.cancel()
    }

    /// Applies the wall clock to the timer; called by the ticker and exposed for tests.
    func tick() async {
        now = clock()
        let advance = timer.advance(now: now)
        if !advance.sessions.isEmpty { record(advance.sessions) }
        if advance.enteredRest {
            await notifier?.notifyFinished(title: "Cátedra: enfoque terminado",
                                           body: "Descanse \(settings().clamped.breakMinutes) min.")
        }
        if advance.finishedRest {
            activityName = nil
            await notifier?.notifyFinished(title: "Cátedra: fin del descanso", body: "Puede iniciar otra sesión de enfoque.")
        }
        if !timer.isRunning { ticker?.cancel() }
    }

    private func record(_ new: [FocusSession]) {
        sessions.append(contentsOf: new)
        try? store.save(sessions)
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                await self.tick()
            }
        }
    }
}
