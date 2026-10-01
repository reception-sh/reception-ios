import Foundation

extension ChatModel {
    /// Conversation messages and sending permission have already been merged, so acknowledged IDs cannot resend.
    func resumeLimitHeldMessages() {
        guard current, isWatched, canSend, !verificationRequired,
              let session, session.halt == nil else { return }
        for index in messages.indices {
            let message = messages[index]
            guard message.status == .failed, message.retryAfterLimitRelease,
                  cooldown(for: message) == nil else { continue }
            messages[index].awaitsManualRetry = false
            messages[index].heldBy = message.heldBy ?? .messages
            session.retries[message.id] = RetryState()
            limitReleaseRetries.insert(message.id)
        }
        guard !limitReleaseRetries.isEmpty else { return }
        saveMessages()
        cooldownsChanged()
    }

    /// The existing retry driver drains the released IDs. Any new failure or departure ends that batch.
    func pauseLimitReleaseRetries() {
        guard !limitReleaseRetries.isEmpty else { return }
        for index in messages.indices where limitReleaseRetries.contains(messages[index].id) && messages[index].seq == nil {
            messages[index].awaitsManualRetry = true
        }
        limitReleaseRetries.removeAll()
        saveMessages()
    }
}
