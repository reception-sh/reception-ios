import UIKit
import UserNotifications

extension ChatModel {
    var pushPromptSlot: PushPromptSlot {
        let reception = Reception.shared
        return PushPromptDecision.resolve(
            prompt: reception.usesRemoteAppearance ? reception.appearanceConfiguration.activePushPrompt : nil,
            authorization: notificationAuthorization, declined: session?.store.pushPromptDeclined == true,
            answered: pushPromptAnswered, lastSender: messages.last?.sender, lastFailed: messages.last?.status == .failed,
            canWrite: !sendingDisabled && !verificationRequired, pushActive: session?.store.pushActive,
            hidesStatus: Reception.resolvedAppearance.hidesPushStatus)
    }

    func refreshNotificationAuthorization() async {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        guard !Task.isCancelled else { return }
        notificationAuthorization = status
    }

    func continuePushPrompt() {
        guard !pushPromptAnswered else { return }
        pushPromptAnswered = true
        Task {
            let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) == true
            Log.debug(granted ? "Notification prompt answered, granted" : "Notification prompt answered, denied")
            await refreshNotificationAuthorization()
            await Reception.shared.registerForPushIfAuthorized()
        }
    }

    func declinePushPrompt() {
        session?.store.pushPromptDeclined = true
        Log.debug("Notification prompt declined")
    }
}
