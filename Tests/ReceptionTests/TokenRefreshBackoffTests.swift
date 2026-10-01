import XCTest
import os
@testable import Reception

@MainActor
final class TokenRefreshBackoffTests: XCTestCase {
    private let limited = StubURLProtocol.Reply(status: 429,
        body: #"{"error":{"code":"rate_limited","message":"Wait"}}"#, headers: ["Retry-After": "5"])
    private let unavailable = StubURLProtocol.Reply(status: 503,
        body: #"{"error":{"code":"unavailable","message":"Wait"}}"#)

    private func makeSession(clock: RefreshTestClock, replies: [StubURLProtocol.Reply],
                             now: @escaping () -> Date = Date.init) throws -> DeviceSession {
        let remaining = OSAllocatedUnfairLock(initialState: replies)
        StubURLProtocol.install { _ in remaining.withLock { $0.isEmpty ? StubURLProtocol.Reply(body: #"{"token":"fresh"}"#) : $0.removeFirst() } }
        let store = DeviceStore(scope: "refresh-backoff-" + UUID().uuidString, credentialStorage: .init(
            read: { _ in .missing }, save: { _, _ in true }, delete: { _ in true }))
        store.hasStartedChat = true
        store.hasConversation = true
        let api = ReceptionAPI(appId: "app_abcdefghijklmnopqrstuv", baseURL: try XCTUnwrap(URL(string: "https://reception.test")))
        let session = DeviceSession(api: api, store: store, refreshSleep: { try await clock.sleep(for: $0) }, now: now)
        session.credentials = SessionCredentials(sessionSecret: "same-secret", verifiedUserId: "same-user")
        return session
    }

    private func finish(_ session: DeviceSession) {
        session.invalidate()
        StubURLProtocol.uninstall()
    }

    private func failRefresh(_ session: DeviceSession, clock: RefreshTestClock) async throws -> Duration {
        let sleeping = expectation(description: "Shared backoff starts")
        clock.didSleep = sleeping
        do {
            _ = try await session.renewedToken(replacing: session.accessToken)
            XCTFail("The transient failure must reach the caller")
        } catch let error as ReceptionAPIError {
            XCTAssertTrue(ReceptionAPIError.isTransient(error))
        }
        await fulfillment(of: [sleeping], timeout: 2)
        return try XCTUnwrap(clock.delays.last)
    }

    func testRenewalLimitBecomesStoredSessionCooldownWithoutNetworkForWaitingCallers() async throws {
        let clock = RefreshTestClock()
        let time = TestTime()
        let session = try makeSession(clock: clock, replies: [limited], now: { time.now })
        defer { finish(session) }
        do {
            _ = try await session.renewedToken(replacing: nil)
            XCTFail("The limit must reach the caller")
        } catch let error as ReceptionAPIError {
            XCTAssertEqual(error.status, 429)
            XCTAssertEqual(error.retryScope, .session, "An older service without a scope falls back to the renewal route")
        }
        XCTAssertEqual(clock.pendingCount, 0, "A server wait is a stored cooldown, not a shared sleep")
        XCTAssertEqual(session.cooldowns.blocking([.session])?.until, time.now.addingTimeInterval(5))

        let callers = (0..<3).map { _ in Task { try await session.renewedToken(replacing: nil) } }
        for caller in callers {
            let result = await caller.result
            XCTAssertThrowsError(try result.get()) { error in
                XCTAssertEqual((error as? ReceptionAPIError)?.isCooldown, true)
                XCTAssertEqual((error as? ReceptionAPIError)?.retryScope, .session)
            }
        }
        XCTAssertEqual(StubURLProtocol.requests.count, 1, "Waiting callers fail at once and send nothing")
        XCTAssertNil(session.refresh)

        time.now.addTimeInterval(5)
        let token = try await session.renewedToken(replacing: nil)

        XCTAssertEqual(token, "fresh")
        XCTAssertEqual(StubURLProtocol.requests.count, 2)
        XCTAssertEqual(session.credentials?.sessionSecret, "same-secret")
    }

    func testConcurrentRequestersBackOffAfterServerFailure() async throws {
        try await checkSharedDelay(reply: unavailable)
    }

    func testConcurrentRequestersBackOffAfterNetworkFailure() async throws {
        try await checkSharedDelay(reply: StubURLProtocol.Reply(networkError: .networkConnectionLost))
    }

    private func checkSharedDelay(reply: StubURLProtocol.Reply, expectedDelay: Duration? = nil) async throws {
        let clock = RefreshTestClock()
        let session = try makeSession(clock: clock, replies: [reply])
        defer { finish(session) }
        let delay = try await failRefresh(session, clock: clock)
        if let expectedDelay { XCTAssertEqual(delay, expectedDelay) }
        else { XCTAssertGreaterThanOrEqual(delay, .seconds(1.5)); XCTAssertLessThanOrEqual(delay, .seconds(2.5)) }
        let waiting = expectation(description: "Both requesters enter renewal")
        waiting.expectedFulfillmentCount = 2
        let first = Task { waiting.fulfill(); return try await session.renewedToken(replacing: nil) }
        let second = Task { waiting.fulfill(); return try await session.renewedToken(replacing: nil) }
        await fulfillment(of: [waiting], timeout: 2)

        clock.advance(by: delay - .milliseconds(1))
        XCTAssertEqual(clock.pendingCount, 1)
        XCTAssertEqual(StubURLProtocol.requests.count, 1, "No requester may bypass the remaining delay")
        XCTAssertNotNil(session.refresh)
        XCTAssertEqual(session.credentials?.sessionSecret, "same-secret")
        XCTAssertEqual(session.credentials?.verifiedUserId, "same-user")
        XCTAssertTrue(session.store.hasConversation)
        XCTAssertFalse(session.invalidated)
        XCTAssertNil(session.halt)

        clock.advance(by: .milliseconds(1))
        let tokens = try await [first.value, second.value]
        XCTAssertEqual(tokens, ["fresh", "fresh"])
        XCTAssertEqual(StubURLProtocol.requests.count, 2, "The waiters share one recovery refresh")
        for request in StubURLProtocol.requests {
            XCTAssertEqual(request.path, "/v1/devices/me/token")
            XCTAssertNil(request.authorization)
            let body = try XCTUnwrap(request.body)
            XCTAssertEqual(try JSONSerialization.jsonObject(with: body) as? [String: String], ["sessionSecret": "same-secret"])
        }
    }

    func testInvalidationCancelsBackoffAndWaitingRefresh() async throws {
        let clock = RefreshTestClock()
        let session = try makeSession(clock: clock, replies: [unavailable])
        defer { finish(session) }
        _ = try await failRefresh(session, clock: clock)
        let entered = expectation(description: "Requester waits for backoff")
        let waiting = Task { entered.fulfill(); return try await session.renewedToken(replacing: nil) }
        await fulfillment(of: [entered], timeout: 2)

        session.deactivate()
        let result = await waiting.result

        XCTAssertThrowsError(try result.get())
        XCTAssertEqual(clock.pendingCount, 0)
        clock.advance(by: .seconds(60))
        XCTAssertEqual(StubURLProtocol.requests.count, 1)
        XCTAssertNil(session.accessToken)
    }

    func testBackoffGrowsAcrossFailuresAndRestartsAfterSuccess() async throws {
        let clock = RefreshTestClock()
        let success = StubURLProtocol.Reply(body: #"{"token":"fresh"}"#)
        let session = try makeSession(clock: clock, replies: [unavailable, unavailable, success, unavailable])
        defer { finish(session) }
        let first = try await failRefresh(session, clock: clock)
        clock.advance(by: first)
        let second = try await failRefresh(session, clock: clock)
        XCTAssertGreaterThanOrEqual(first, .seconds(1.5))
        XCTAssertLessThanOrEqual(first, .seconds(2.5))
        XCTAssertGreaterThanOrEqual(second, .seconds(3))
        XCTAssertLessThanOrEqual(second, .seconds(5))
        clock.advance(by: second)
        _ = try await session.renewedToken(replacing: nil)

        let afterSuccess = try await failRefresh(session, clock: clock)

        XCTAssertGreaterThanOrEqual(afterSuccess, .seconds(1.5))
        XCTAssertLessThanOrEqual(afterSuccess, .seconds(2.5))
        XCTAssertEqual(session.accessToken, "fresh")
        XCTAssertEqual(session.credentials?.sessionSecret, "same-secret")
        clock.advance(by: afterSuccess)
    }

    func testNewerCachedTokenCanBeUsedWithoutWaitingOrProactiveRefresh() async throws {
        let clock = RefreshTestClock()
        let session = try makeSession(clock: clock, replies: [unavailable])
        defer { finish(session) }
        let delay = try await failRefresh(session, clock: clock)
        session.accessToken = "newer"

        let token = try await session.renewedToken(replacing: "older")

        XCTAssertEqual(token, "newer")
        XCTAssertEqual(clock.pendingCount, 1)
        clock.advance(by: delay)
        XCTAssertEqual(StubURLProtocol.requests.count, 1)
    }
}
