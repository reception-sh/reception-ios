import XCTest

/// Advances only when the test asks; cancellation still behaves like Task.sleep.
@MainActor
final class RefreshTestClock {
    private struct Waiter {
        let deadline: Duration
        let continuation: CheckedContinuation<Void, Error>
    }
    private var now: Duration = .zero
    private var waiters: [UUID: Waiter] = [:]
    private(set) var delays: [Duration] = []
    var didSleep: XCTestExpectation?
    var pendingCount: Int { waiters.count }

    func sleep(for delay: Duration) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { continuation in
                waiters[id] = Waiter(deadline: now + delay, continuation: continuation)
                delays.append(delay)
                didSleep?.fulfill()
            }
        } onCancel: {
            Task { @MainActor in
                self.waiters.removeValue(forKey: id)?.continuation.resume(throwing: CancellationError())
            }
        }
    }

    func advance(by duration: Duration) {
        now += duration
        let ready = waiters.filter { $0.value.deadline <= now }
        for (id, waiter) in ready {
            waiters.removeValue(forKey: id)
            waiter.continuation.resume()
        }
    }
}
