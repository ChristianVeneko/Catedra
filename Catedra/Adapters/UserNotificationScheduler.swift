import Foundation
import UserNotifications

/// `UNUserNotificationCenter` implementation of deadline reminders.
struct UserNotificationScheduler: NotificationScheduling {
    static let activityIDKey = "activityID"
    static let testIdentifier = "catedra.test"

    func permission() async -> NotificationPermission {
        Self.map(await UNUserNotificationCenter.current().notificationSettings().authorizationStatus)
    }

    func requestPermission() async -> NotificationPermission {
        let center = UNUserNotificationCenter.current()
        if await permission() == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
        return await permission()
    }

    func pendingDeadlineIDs() async -> Set<String> {
        let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        return Set(requests.map(\.identifier).filter { $0.hasPrefix(DeadlineReminderPlanner.idPrefix) })
    }

    func apply(_ diff: DeadlineReminderPlanner.Diff, now: Date) async {
        let center = UNUserNotificationCenter.current()
        if !diff.toRemove.isEmpty { center.removePendingNotificationRequests(withIdentifiers: diff.toRemove) }
        for reminder in diff.toAdd {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            content.userInfo = [Self.activityIDKey: reminder.activityID]
            // Relative trigger: immune to time-zone changes between scheduling and firing.
            let interval = max(1, reminder.fireDate.timeIntervalSince(now))
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger))
        }
    }

    func sendTest() async {
        let content = UNMutableNotificationContent()
        content.title = "Vence en 24 h: Notificación de prueba"
        content.body = "Cátedra · Prueba · Así se verán los recordatorios"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: Self.testIdentifier, content: content, trigger: trigger))
    }

    private static func map(_ status: UNAuthorizationStatus) -> NotificationPermission {
        switch status {
        case .notDetermined: .notDetermined
        case .denied: .denied
        default: .authorized
        }
    }
}

/// Shows deadline notifications while the app is frontmost and routes a tap to the activity.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    /// Set on the main actor by the composition root.
    @MainActor var onOpenActivity: ((String) -> Void)?

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let id = response.notification.request.content.userInfo[UserNotificationScheduler.activityIDKey] as? String else { return }
        await MainActor.run { onOpenActivity?(id) }
    }
}
