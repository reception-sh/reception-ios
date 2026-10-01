import Reception
import UIKit
import UserNotifications

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Task { await registerIfAuthorized() }
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken token: Data) {
        Reception.shared.setPushToken(token)
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Failed to register for remote notifications: \(error)")
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        let payload = notification.request.content.userInfo["reception"] as? [String: Any]
        if let conversationId = payload?["conversationId"] as? String {
            let options: UNNotificationPresentationOptions? = await MainActor.run {
                guard Reception.shared.handlePushNotification(
                    userInfo: ["reception": ["conversationId": conversationId]],
                    openChat: false
                ) else { return nil }
                return Reception.shared.isChatOpen ? [] : [.banner, .sound]
            }
            if let options { return options }
        }
        return [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let payload = response.notification.request.content.userInfo["reception"] as? [String: Any]
        guard let conversationId = payload?["conversationId"] as? String else { return }
        await MainActor.run {
            _ = Reception.shared.handlePushNotification(userInfo: ["reception": ["conversationId": conversationId]])
        }
    }
}
