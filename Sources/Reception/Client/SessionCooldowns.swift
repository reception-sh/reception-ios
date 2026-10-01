import Foundation

extension DeviceSession {
    /// Rejects work that a known cooldown covers before it reaches the network. The rejection makes no attempt,
    /// so it never spends the retry budget.
    func admit(_ scopes: [RetryScope]) throws {
        guard let cooldown = cooldowns.blocking(scopes) else { return }
        Log.debug("Request skipped, \(cooldown.scope.rawValue) paused")
        let remaining = cooldown.until.timeIntervalSince(cooldowns.now()).rounded(.up)
        throw ReceptionAPIError(code: "cooldown", status: 0, retryAfter: Int(max(1, remaining)), retryScope: cooldown.scope)
    }

    /// Only a response of the service starts a cooldown; storage replies never reach this path.
    func imposeCooldown(for error: ReceptionAPIError) {
        guard error.status > 0, let scope = error.retryScope, let seconds = error.retryAfter else { return }
        cooldowns.impose(scope, seconds: seconds)
    }

    func cooldownsChanged() {
        guard !invalidated, self === Reception.shared.session else { return }
        Reception.shared.chat?.cooldownsChanged()
    }
}
