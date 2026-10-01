import Foundation

/// How a failed message can be sent again.
internal enum RetryAvailability: Equatable {
    case now
    /// A short wait ends in an automatic resend while the chat stays visible; the person can cancel it.
    case automatic(Date)
    /// A cooldown holds the message; the notice above the composer explains the wait.
    case waiting
}

internal struct AutomaticRetry {
    let messageId: String
    let id: UUID
    let task: Task<Void, Never>
}

extension ChatModel {
    private static let textScopes: [RetryScope] = [.messages, .requests, .session]

    var cooldowns: ServerCooldowns? { current ? session?.cooldowns : nil }

    /// The chat is on screen in an active app, including while its first load is still running.
    var isWatched: Bool { isVisible && Reception.shared.applicationActive }

    /// Everything a send of this message needs; photos also wait for the upload limits.
    func cooldownScopes(for message: Message) -> [RetryScope] {
        message.images.isEmpty && message.attachmentIds.isEmpty ? Self.textScopes : Self.textScopes + [.uploads]
    }

    func cooldown(for message: Message) -> ServerCooldowns.Cooldown? {
        cooldowns?.blocking(cooldownScopes(for: message))
    }

    /// The wait explained above the composer: whatever stops text first, then a photo-only wait.
    var composerCooldown: ServerCooldowns.Cooldown? {
        cooldowns?.blocking(Self.textScopes) ?? cooldowns?.blocking([.uploads])
    }

    /// New sends also wait while held messages go out again, so nothing overtakes them.
    func cooldownAllowsSend(photos: Bool) -> Bool {
        cooldowns?.blocking(photos ? Self.textScopes + [.uploads] : Self.textScopes) == nil && !resendingHeldMessages
    }

    private var resendingHeldMessages: Bool {
        messages.contains { message in
            message.heldBy != nil && !message.awaitsManualRetry && (message.status == .sending
                || (retriesAutomatically(message) && cooldown(for: message) == nil))
        }
    }

    var photosPaused: Bool { cooldowns?.blocking([.uploads]) != nil }

    var streamPaused: Bool { cooldowns?.blocking([.stream, .requests, .session]) != nil }

    func retryAvailability(for message: Message) -> RetryAvailability {
        guard message.status == .failed, let cooldown = cooldown(for: message) else { return .now }
        return cooldown.automatic && retriesAutomatically(message) ? .automatic(cooldown.until) : .waiting
    }

    /// Failed messages resend on their own unless the person must decide or the retry budget is spent.
    func retriesAutomatically(_ message: Message) -> Bool {
        message.status == .failed && !message.awaitsManualRetry && isWatched
            && session?.retries[message.id].map { !$0.stopped } == true
    }

    /// The person keeps the message and sends it again later with Retry. Held messages after it stop too,
    /// so none of them overtakes it.
    func cancelAutomaticRetry(messageId: String) {
        guard let start = messages.firstIndex(where: { $0.id == messageId }), messages[start].status == .failed else { return }
        for index in messages.indices[start...] where heldForAutomaticResend(messages[index])
            || messages[index].retryAfterLimitRelease || messages[index].retryAfterTransientFailure || index == start {
            messages[index].awaitsManualRetry = true
            messages[index].retryAfterLimitRelease = false
            messages[index].retryAfterTransientFailure = false
            limitReleaseRetries.remove(messages[index].id)
        }
        saveMessages()
        // A resend of an earlier message continues; only a driver waiting on a canceled message stops.
        guard let target = automaticRetry?.messageId, messages.firstIndex(where: { $0.id == target }).map({ $0 >= start }) != false
        else { return }
        cancelAutomaticRetry()
        retryFailedAutomatically()
    }

    private func heldForAutomaticResend(_ message: Message) -> Bool {
        message.status == .failed && !message.awaitsManualRetry && (message.heldBy != nil || cooldown(for: message) != nil)
    }

    func cancelAutomaticRetry() {
        automaticRetry?.task.cancel()
        automaticRetry = nil
    }

    /// Short waits resend only while the person watches; closing the chat or leaving the app makes them manual,
    /// including held messages whose wait just ended and that were still queued.
    func deferCooldownRetries() {
        pauseLimitReleaseRetries()
        var deferred = false
        for index in messages.indices where heldForAutomaticResend(messages[index]) {
            messages[index].awaitsManualRetry = true
            deferred = true
        }
        if deferred { saveMessages() }
    }

    func cooldownsChanged() {
        if messages.contains(where: { limitReleaseRetries.contains($0.id) && cooldown(for: $0) != nil }) {
            pauseLimitReleaseRetries()
        }
        refreshConnection()
        retryFailedAutomatically()
        // Changes signalled during a request wait were skipped; catch up once it ends.
        guard pollDeferred, cooldowns?.blocking([.requests]) == nil else { return }
        pollDeferred = false
        Task { await poll() }
    }
}
