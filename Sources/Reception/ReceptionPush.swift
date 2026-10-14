import UIKit
import UserNotifications

extension Reception {
    /// Registers with APNs only when notification permission already exists. Never requests permission.
    /// Call at launch, on foreground, after your permission flow, and after logout or successful deletion.
    public func registerForPushIfAuthorized() async {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        if PushAuthorization.allowsRegistration(status) {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    /// Handles foreground receipt and returns Reception's presentation policy, or nil for another notification.
    /// Call from `willPresent`; keep your own policy when this returns nil.
    nonisolated public func notificationPresentationOptions(
        userInfo: [AnyHashable: Any]
    ) async -> UNNotificationPresentationOptions? {
        guard let id = Self.pushConversationId(userInfo) else { return nil }
        return await MainActor.run {
            self.handlePushNotification(userInfo: ["reception": ["conversationId": id]], openChat: false)
            return self.isChatOpen ? [] : [.banner, .sound]
        }
    }

    /// Routes a notification tap from a notification-center delegate without transferring its raw payload across actors.
    @discardableResult
    nonisolated public func handlePushNotification(_ response: UNNotificationResponse) async -> Bool {
        guard let id = Self.pushConversationId(response.notification.request.content.userInfo) else { return false }
        return await MainActor.run {
            self.handlePushNotification(userInfo: ["reception": ["conversationId": id]])
        }
    }

    nonisolated internal static func pushConversationId(_ userInfo: [AnyHashable: Any]) -> String? {
        guard let payload = userInfo["reception"] as? [String: Any],
              let id = payload["conversationId"] as? String, !id.isEmpty else { return nil }
        return id
    }
}

internal enum PushAuthorization {
    static func allowsRegistration(_ status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral: true
        default: false
        }
    }
}
