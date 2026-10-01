import UIKit
import UserNotifications

@MainActor
internal final class UnreadMonitor: NSObject {
    private var task: Task<Void, Never>?
    private var authorizationTask: Task<Void, Never>?
    private var notificationsAuthorized = false
    private var enabled = false
    private var active = false

    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(becameActive),
            name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(enteredBackground),
            name: UIApplication.didEnterBackgroundNotification, object: nil)
    }

    @objc private func becameActive() {
        Reception.shared.session?.becameActive()
        if enabled { setActive(true, foreground: true) }
    }
    @objc private func enteredBackground() { if enabled { setActive(false) } }

    func setActive(_ active: Bool, foreground: Bool = false) {
        enabled = true
        self.active = active
        task?.cancel()
        task = nil
        authorizationTask?.cancel()
        authorizationTask = nil
        guard active else {
            Reception.shared.cancelUnreadRefresh()
            Reception.shared.session?.suspendPreferenceRetry()
            return
        }
        authorizationTask = Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            guard !Task.isCancelled, self.active else { return }
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                notificationsAuthorized = true
            default:
                notificationsAuthorized = false
            }
            authorizationTask = nil
            guard Reception.shared.session?.store.hasStartedChat == true else { return }
            let blockedProbe = foreground && Reception.shared.session?.halt == .blocked
            Reception.shared.refreshUnread(updateDevice: !blockedProbe, probe: blockedProbe)
        }
    }

    func reschedule() {
        task?.cancel()
        task = nil
        let reception = Reception.shared
        guard active, authorizationTask == nil, UIApplication.shared.applicationState == .active,
              reception.session?.halt == nil, reception.session?.retries["unread"]?.stopped != true,
              let store = reception.session?.store, store.hasConversation, !reception.isChatOpen else { return }
        let lastActivity = [store.lastMessageAt, store.chatCache.latestMessageAt].compactMap { $0 }.max()
        let pushActive = store.pushActive == true && notificationsAuthorized
        guard let interval = UnreadSchedule.interval(status: store.conversationStatus, lastActivity: lastActivity,
                                                     push: pushActive, stages: store.unreadPolling, now: Date()) else { return }
        task = Task {
            do { try await Task.sleep(for: .seconds(interval)) } catch { return }
            guard !Task.isCancelled, active, UIApplication.shared.applicationState == .active,
                  reception.session?.halt == nil, reception.session?.store.hasConversation == true, !reception.isChatOpen else { return }
            task = nil
            reception.refreshUnread()
        }
    }
}
