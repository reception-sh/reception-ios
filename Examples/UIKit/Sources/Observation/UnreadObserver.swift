import Observation
import Reception

@MainActor
func observeUnreadCount(_ handler: @escaping @MainActor @Sendable (Int) -> Void) {
    let count = withObservationTracking {
        Reception.shared.unreadCount
    } onChange: {
        Task { @MainActor in
            observeUnreadCount(handler)
        }
    }
    handler(count)
}
