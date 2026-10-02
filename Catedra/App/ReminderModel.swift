import Foundation
import Observation

/// Keeps the system's pending notifications in sync with the planned deadline reminders.
@Observable @MainActor
final class ReminderModel {
    private(set) var permission: NotificationPermission = .notDetermined
    private(set) var scheduledCount = 0

    private let scheduler: NotificationScheduling
    private let settings: SettingsModel
    private let workspace: WorkspaceModel
    private let now: @MainActor () -> Date
    private var task: Task<Void, Never>?

    init(scheduler: NotificationScheduling, settings: SettingsModel, workspace: WorkspaceModel,
         now: @escaping @MainActor () -> Date = { .now }) {
        self.scheduler = scheduler
        self.settings = settings
        self.workspace = workspace
        self.now = now
    }

    func refreshPermission() async {
        permission = await scheduler.permission()
    }

    /// Debounced, serialized re-plan; safe to call from every reload and settings change.
    func scheduleSoon() {
        task?.cancel()
        task = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await self?.reschedule()
        }
    }

    func reschedule() async {
        let prefs = settings.reminders
        var current = await scheduler.permission()
        if prefs.enabled, current == .notDetermined { current = await scheduler.requestPermission() }
        permission = current
        let date = now()
        let planned: [DeadlineReminder] = prefs.enabled && current == .authorized
            ? DeadlineReminderPlanner.plan(
                activities: workspace.snapshot.activities,
                stateOf: { [workspace] in workspace.state(of: $0, now: date) },
                now: date, offsetsHours: prefs.offsetsHours)
            : []
        let diff = DeadlineReminderPlanner.diff(planned: planned, pendingIDs: await scheduler.pendingDeadlineIDs())
        await scheduler.apply(diff, now: date)
        scheduledCount = planned.count
    }

    func sendTest() async {
        permission = await scheduler.requestPermission()
        guard permission == .authorized else { return }
        await scheduler.sendTest()
    }
}
