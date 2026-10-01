import UIKit
import UserNotifications

/// Registers with APNs only if notification permission is already granted; never prompts.
/// Shared by the app delegate's launch check and the scene-phase recheck in the App.
@MainActor
func registerIfAuthorized() async {
    let settings = await UNUserNotificationCenter.current().notificationSettings()
    switch settings.authorizationStatus {
    case .authorized, .provisional, .ephemeral:
        UIApplication.shared.registerForRemoteNotifications()
    default:
        break
    }
}
