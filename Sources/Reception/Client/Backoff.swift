import Foundation

internal enum Backoff {
    static func delay(attempt: Int) -> Duration {
        .seconds(min(2 * pow(2, Double(max(0, min(attempt - 1, 6)))), 60) * Double.random(in: 0.75...1.25))
    }
}

/// Retained across task cancellation and view changes; only foreground or explicit user actions reset it.
internal struct RetryState {
    private(set) var attempts = 0
    private(set) var stopped = false
    private var transient = false
    private(set) var nextAttempt: Date?

    mutating func failed(_ error: Error) {
        if let error = error as? ReceptionAPIError, error.isCooldown {
            // A known cooldown kept the request off the network: wait for it without spending an attempt.
            nextAttempt = Date().addingTimeInterval(TimeInterval(error.retryAfter ?? 0))
            return
        }
        attempts += 1
        transient = ReceptionAPIError.isTransient(error)
        guard transient else { stopped = true; nextAttempt = nil; return }
        guard attempts < 8 else {
            stopped = true
            nextAttempt = nil
            Log.debug("Retries paused after \(attempts) attempts until the app becomes active")
            return
        }
        let delay = (error as? ReceptionAPIError)?.retryAfter.map { Duration.seconds($0) }
            ?? Backoff.delay(attempt: attempts)
        let seconds = Double(delay.components.seconds) + Double(delay.components.attoseconds) / 1e18
        nextAttempt = Date().addingTimeInterval(seconds)
        Log.debug("Retry scheduled in \(String(format: "%.2f", seconds))s, attempt \(attempts + 1)")
    }

    var delay: Duration? {
        guard !stopped, let nextAttempt else { return nil }
        return .seconds(max(0, nextAttempt.timeIntervalSinceNow))
    }

    mutating func foreground() {
        // Non-retryable failures stay stopped. The foreground renews the budget for transient work.
        guard transient else { return }
        self = RetryState()
    }
}

@MainActor
internal final class RequestProbe {
    var available = true
}

internal enum RequestContext {
    @TaskLocal static var probe: RequestProbe?
}
