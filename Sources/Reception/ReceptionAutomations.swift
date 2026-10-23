import Foundation

extension Reception {
    /// Reports that something happened in your app, for example `"paywall_declined"`. When an automation in your
    /// dashboard listens for the event, Reception sends its message and opens the chat. Other events stay on the device.
    ///
    /// With `opensChat`, the chat also opens again at later events for people who received an enabled automation's
    /// message that opens the chat, so they find it again. For example when a paywall closes without a purchase. People
    /// the automation doesn't reach, because its rules exclude them or its message comes later or as a push, see nothing.
    ///
    /// Names use 1–64 letters, digits, underscores, dots or hyphens. Returns at once and never fails: offline,
    /// on a server error or when the automation does not apply, no message comes.
    public func track(_ event: String, opensChat: Bool = false) {
        guard let session else {
            Log.error("track called before configure, ignored")
            return
        }
        guard Automations.accepts(event) else {
            Log.error("track refused a malformed event name; use 1–64 letters, digits, underscores, dots or hyphens")
            return
        }
        automations.track(event, opensChat: opensChat, session: session)
    }

    /// Reads the App Store at configure and foreground: whether the person pays, for automations that skip or target
    /// subscribers, and whether a trial or subscription was cancelled, failed to renew or ran out.
    func checkSubscriptions() {
        paidAccess.start { [weak self] in
            guard let session = self?.session else { return }
            self?.automations.subscriptionChanged(session: session)
        }
        guard let session else { return }
        automations.checkSubscriptions(session: session)
    }
}
