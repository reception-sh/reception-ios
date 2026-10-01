import UserNotifications

@MainActor internal enum AppBadge {
    private static var generation = 0
    private static var pending: Task<Void, Never>?

    static func sync(_ count: Int) {
        generation &+= 1
        guard Reception.shared.updatesAppBadge else { return }
        let expected = generation
        let session = Reception.shared.session
        let previous = pending
        pending = Task {
            // Serialize OS writes: an already submitted old write must finish before the newest one.
            await previous?.value
            guard Reception.shared.updatesAppBadge, expected == generation, session === Reception.shared.session else { return }
            let center = UNUserNotificationCenter.current()
            try? await center.setBadgeCount(count)
            if count == 0 {
                let notifications = await center.deliveredNotifications()
                guard Reception.shared.updatesAppBadge, expected == generation, session === Reception.shared.session else { return }
                let identifiers = notifications
                    .filter { $0.request.content.userInfo["reception"] != nil }
                    .map { $0.request.identifier }
                center.removeDeliveredNotifications(withIdentifiers: identifiers)
            }
            if expected == generation { pending = nil }
        }
    }
}
