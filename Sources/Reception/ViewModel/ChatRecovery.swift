import Foundation

extension ChatModel {
    /// Quota waits retain their separate release/cancel policy; older failed caches stay manual.
    static func isRecoverableSubmissionFailure(_ error: Error) -> Bool {
        if let error = error as? ReceptionAPIError,
           error.isCooldown || error.status == 429 || error.retryScope != nil { return false }
        return ReceptionAPIError.isTransient(error)
    }

    /// Restore missing process-local budgets only. Reopening must not renew an active or spent budget.
    func resumeTransientFailures() {
        guard current, !Task.isCancelled, isWatched, canSend, !verificationRequired,
              let session, session.halt == nil else { return }
        for message in messages where message.status == .failed && message.retryAfterTransientFailure
            && !message.awaitsManualRetry && cooldown(for: message)?.automatic != false && session.retries[message.id] == nil {
            session.retries[message.id] = RetryState()
        }
        retryFailedAutomatically()
    }
}
