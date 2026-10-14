import UIKit
import UserNotifications

/// Turns ntfy messages into local notifications — no APNs, nothing goes through Apple servers.
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
    }

    func requestAuthorization() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func post(_ message: NtfyMessage, serverName: String?) {
        let content = UNMutableNotificationContent()
        content.title = message.notificationHeader(serverName: serverName)
        content.body = message.notificationBody
        content.threadIdentifier = "\(message.serverID?.uuidString ?? "")/\(message.topic)"
        content.userInfo = ["id": message.id, "topic": message.topic, "click": message.click ?? ""]

        // ntfy priorities: 1 min, 2 low, 3 default, 4 high, 5 max.
        switch message.effectivePriority {
        case ...2:
            content.interruptionLevel = .passive
        case 3:
            content.interruptionLevel = .active
            content.sound = .default
        default:
            // Without the time-sensitive entitlement iOS falls back to .active.
            content.interruptionLevel = .timeSensitive
            content.sound = .default
        }

        center.add(UNNotificationRequest(identifier: message.id, content: content, trigger: nil))
    }

    // Show banners while the app is in the foreground too.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let click = response.notification.request.content.userInfo["click"] as? String,
           let url = URL(string: click), url.scheme != nil {
            DispatchQueue.main.async { UIApplication.shared.open(url) }
        }
        completionHandler()
    }
}
