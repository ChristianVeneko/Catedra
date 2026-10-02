import AppKit
import UserNotifications

/// Local notifications for finished runs, only when the app is not frontmost.
struct UserNotificationAdapter: AgentNotifying {
    func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    func notifyFinished(title: String, body: String) async {
        let isActive = await MainActor.run { NSApplication.shared.isActive }
        guard !isActive else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
