import Foundation

enum NotificationPermission: Sendable, Equatable {
    case notDetermined, denied, authorized
}

/// Schedules local deadline notifications. Implementations only ever touch requests whose id starts with
/// `DeadlineReminderPlanner.idPrefix` (plus the explicit test notification).
protocol NotificationScheduling: Sendable {
    func permission() async -> NotificationPermission
    /// Asks the system for permission (shows the prompt only while undetermined) and returns the resulting state.
    func requestPermission() async -> NotificationPermission
    func pendingDeadlineIDs() async -> Set<String>
    func apply(_ diff: DeadlineReminderPlanner.Diff, now: Date) async
    func sendTest() async
}
