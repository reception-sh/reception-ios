import XCTest
import os
@testable import Reception

/// Known cooldowns gate actual network work: scope isolation, persistence and the retry budget.
@MainActor
final class CooldownGateTests: XCTestCase {
    private let time = TestTime()

    nonisolated private static func limited(_ scope: String?, seconds: Int = 30, status: Int = 429) -> StubURLProtocol.Reply {
        let field = scope.map { #","retryScope":"\#($0)""# } ?? ""
        return StubURLProtocol.Reply(status: status, body: #"{"error":{"code":"rate_limited","message":"Wait"\#(field)}}"#,
                                     headers: ["Retry-After": String(seconds)])
    }

    private func makeSession(scope: String = "gate-" + UUID().uuidString, registered: Bool = true,
                             _ responder: @escaping StubURLProtocol.Responder) throws -> DeviceSession {
        StubURLProtocol.install(responder)
        let store = DeviceStore(scope: scope, credentialStorage: .init(read: { _ in .missing }, save: { _, _ in true },
                                                                      delete: { _ in true }))
        store.hasStartedChat = true
        let api = ReceptionAPI(appId: "app_abcdefghijklmnopqrstuv", baseURL: try XCTUnwrap(URL(string: "https://reception.test")))
        let session = DeviceSession(api: api, store: store, now: { [time] in time.now })
        if registered {
            session.credentials = SessionCredentials(sessionSecret: "secret", verifiedUserId: nil)
            session.accessToken = "access"
        }
        return session
    }

    private func finish(_ session: DeviceSession) {
        session.invalidate()
        StubURLProtocol.uninstall()
    }

    private func post(_ session: DeviceSession, _ path: String, photos: Bool = false) async throws {
        let _: EmptyResponse = try await session.api.request(path, method: "POST", authenticated: true, body: Data("{}".utf8),
                                                             photos: photos)
    }

    private func expectCooldown(_ scope: RetryScope, _ work: () async throws -> Void) async {
        do {
            try await work()
            XCTFail("A known cooldown must hold the request")
        } catch {
            XCTAssertEqual((error as? ReceptionAPIError)?.isCooldown, true)
            XCTAssertEqual((error as? ReceptionAPIError)?.retryScope, scope)
        }
    }

    private var paths: [String] { StubURLProtocol.requests.map(\.path) }

    func testMessageCooldownGatesOnlyMessagePosts() async throws {
        let session = try makeSession { request in
            request.path == "/v1/conversation/messages" ? Self.limited("messages") : StubURLProtocol.Reply()
        }
        defer { finish(session) }
        do { try await post(session, "conversation/messages"); XCTFail("The limit must reach the caller") } catch {}

        await expectCooldown(.messages) { try await self.post(session, "conversation/messages") }
        let _: EmptyResponse = try await session.api.request("conversation/unread", authenticated: true)
        try await post(session, "uploads")

        XCTAssertEqual(paths, ["/v1/conversation/messages", "/v1/conversation/unread", "/v1/uploads"])
        XCTAssertEqual(session.cooldowns.blocking([.messages])?.until, time.now.addingTimeInterval(30))
        XCTAssertEqual(session.cooldowns.blocking([.messages])?.automatic, true)
    }

    func testRequestLimitDuringUploadIsNotAnUploadWaitAndDeletionStaysPossible() async throws {
        let session = try makeSession { request in
            request.path == "/v1/uploads" ? Self.limited("requests", seconds: 40) : StubURLProtocol.Reply()
        }
        defer { finish(session) }
        do { try await post(session, "uploads"); XCTFail("The limit must reach the caller") } catch {}

        XCTAssertNil(session.cooldowns.blocking([.uploads]))
        await expectCooldown(.requests) { try await self.post(session, "conversation/messages") }
        await expectCooldown(.requests) {
            let _: EmptyResponse = try await session.api.request("conversation/unread", authenticated: true)
        }
        try await session.api.deleteDevice(sessionSecret: "secret")

        XCTAssertEqual(paths, ["/v1/uploads", "/v1/devices/me"])
    }

    func testUploadCooldownLeavesTextMessagesAvailable() async throws {
        let session = try makeSession { request in
            request.path == "/v1/uploads" ? Self.limited("uploads", seconds: 600) : StubURLProtocol.Reply()
        }
        defer { finish(session) }
        do { try await post(session, "uploads"); XCTFail("The limit must reach the caller") } catch {}

        await expectCooldown(.uploads) { try await self.post(session, "uploads") }
        await expectCooldown(.uploads) { try await self.post(session, "conversation/messages", photos: true) }
        try await post(session, "conversation/messages")

        XCTAssertEqual(paths, ["/v1/uploads", "/v1/conversation/messages"])
        XCTAssertEqual(session.cooldowns.blocking([.uploads])?.automatic, false)
    }

    func testScopedCapacity503IsABriefPhotoWaitButUnscoped503IsNot() async throws {
        let session = try makeSession { request in
            request.path == "/v1/uploads"
                ? Self.limited("uploads", seconds: 2, status: 503)
                : StubURLProtocol.Reply(status: 503, body: #"{"error":{"code":"uploads_unavailable","message":"Down"}}"#)
        }
        defer { finish(session) }
        do { try await post(session, "conversation/messages"); XCTFail("The failure must reach the caller") } catch {}
        XCTAssertTrue(session.cooldowns.active.isEmpty, "An unscoped 503 keeps ordinary backoff")
        do { try await post(session, "uploads"); XCTFail("The failure must reach the caller") } catch {}

        XCTAssertEqual(session.cooldowns.blocking([.uploads])?.until, time.now.addingTimeInterval(2))
        XCTAssertEqual(session.cooldowns.blocking([.uploads])?.automatic, true)
        XCTAssertNil(session.cooldowns.blocking([.messages, .requests, .session]))
    }

    func testCooldownArrivingWhileWaitingForTokenStillHoldsTheRequest() async throws {
        let gate = StubURLProtocol.Gate()
        let refreshing = expectation(description: "Renewal started")
        let session = try makeSession { request in
            guard request.path == "/v1/devices/me/token" else { return StubURLProtocol.Reply() }
            refreshing.fulfill()
            return StubURLProtocol.Reply(body: #"{"token":"fresh"}"#, gate: gate)
        }
        defer { finish(session) }
        session.accessToken = nil
        let send = Task { try await self.post(session, "conversation/messages") }
        await fulfillment(of: [refreshing], timeout: 2)

        // A sibling's response arrives while this request is suspended on its token.
        session.cooldowns.impose(.messages, seconds: 20)
        gate.release()
        let result = await send.result

        XCTAssertThrowsError(try result.get()) { XCTAssertEqual(($0 as? ReceptionAPIError)?.isCooldown, true) }
        XCTAssertEqual(paths, ["/v1/devices/me/token"])
        XCTAssertEqual(session.accessToken, "fresh")
    }

    func testCooldownArrivingDuringRenewalAfterA401StillHoldsTheResend() async throws {
        let gate = StubURLProtocol.Gate()
        let renewing = expectation(description: "Renewal after 401 started")
        let session = try makeSession { request in
            if request.path == "/v1/devices/me/token" {
                renewing.fulfill()
                return StubURLProtocol.Reply(body: #"{"token":"fresh"}"#, gate: gate)
            }
            return StubURLProtocol.Reply(status: 401, body: #"{"error":{"code":"unauthorized","message":"Expired"}}"#)
        }
        defer { finish(session) }
        let send = Task { try await self.post(session, "conversation/messages") }
        await fulfillment(of: [renewing], timeout: 2)

        session.cooldowns.impose(.messages, seconds: 20)
        gate.release()
        let result = await send.result

        XCTAssertThrowsError(try result.get()) { XCTAssertEqual(($0 as? ReceptionAPIError)?.isCooldown, true) }
        XCTAssertEqual(paths, ["/v1/conversation/messages", "/v1/devices/me/token"], "No second message POST")
    }

    func testRegistrationLimitBeforeCredentialsIsASessionCooldown() async throws {
        let session = try makeSession(registered: false) { _ in Self.limited(nil, seconds: 120) }
        defer { finish(session) }
        session.registrationAllowed = true
        do { _ = try await session.token(); XCTFail("The limit must reach the caller") } catch let error as ReceptionAPIError {
            XCTAssertEqual(error.status, 429)
            XCTAssertEqual(error.retryScope, .session)
        }

        await expectCooldown(.session) { _ = try await session.token() }
        await expectCooldown(.session) { try await self.post(session, "conversation/messages") }

        XCTAssertEqual(paths, ["/v1/devices"])
        XCTAssertNil(session.credentials)
        XCTAssertEqual(session.cooldowns.blocking([.session])?.automatic, false)
    }

    func testStreamLimitPausesOnlyTheStream() async throws {
        let session = try makeSession { request in
            request.path == "/v1/conversation/events" ? Self.limited("stream", seconds: 60) : StubURLProtocol.Reply()
        }
        defer { finish(session) }
        do { _ = try await session.api.stream("conversation/events"); XCTFail("The limit must reach the caller") } catch {}

        await expectCooldown(.stream) { _ = try await session.api.stream("conversation/events") }
        try await post(session, "conversation/messages")

        XCTAssertEqual(paths, ["/v1/conversation/events", "/v1/conversation/messages"])
    }

    func testLateLimitForAReplacedSessionNeverReachesTheNewIdentity() async throws {
        let gate = StubURLProtocol.Gate()
        let sending = expectation(description: "Old session's send is in flight")
        let old = try makeSession { _ in
            sending.fulfill()
            var reply = Self.limited("messages", seconds: 3600)
            reply.gate = gate
            return reply
        }
        defer { finish(old) }
        let send = Task { try await self.post(old, "conversation/messages") }
        await fulfillment(of: [sending], timeout: 2)

        // Logout or a user switch replaces the session while the old response is still on its way.
        old.invalidate()
        let replacement = DeviceSession(api: old.api, store: DeviceStore(scope: "gate-new-" + UUID().uuidString),
                                        now: { [time] in time.now })
        defer { replacement.invalidate() }
        gate.release()
        _ = await send.result

        XCTAssertNil(old.cooldowns.blocking(RetryScope.allCases))
        XCTAssertTrue(old.store.cooldowns.isEmpty, "The cleared namespace is not written again")
        XCTAssertNil(replacement.cooldowns.blocking(RetryScope.allCases))
    }

    func testCooldownsSurviveRelaunchAndChatResetButNotSessionReset() throws {
        let scope = "persist-" + UUID().uuidString
        let session = try makeSession(scope: scope) { _ in StubURLProtocol.Reply() }
        defer { finish(session) }
        session.cooldowns.impose(.messages, seconds: 3600)
        session.cooldowns.impose(.uploads, seconds: 45)

        let relaunched = DeviceSession(api: session.api, store: DeviceStore(scope: scope), now: { [time] in time.now })
        XCTAssertEqual(relaunched.cooldowns.blocking([.messages])?.until, time.now.addingTimeInterval(3600))
        XCTAssertEqual(relaunched.cooldowns.blocking([.messages])?.automatic, false)
        XCTAssertEqual(relaunched.cooldowns.blocking([.uploads])?.automatic, true)
        relaunched.deactivate()

        session.store.resetChat(revision: 4)
        let afterChatReset = DeviceSession(api: session.api, store: session.store.renewed(), now: { [time] in time.now })
        XCTAssertNotNil(afterChatReset.cooldowns.blocking([.messages]), "Support reset keeps the server session")
        afterChatReset.deactivate()

        session.store.clear()
        let afterLogout = DeviceSession(api: session.api, store: DeviceStore(scope: scope), now: { [time] in time.now })
        XCTAssertNil(afterLogout.cooldowns.blocking(RetryScope.allCases))
        afterLogout.deactivate()
    }

    func testConfigurationScopesKeepSeparateCooldownsAcrossAToBToA() throws {
        let scopeA = "https://a.reception.test|app_aaaaaaaaaaaaaaaaaaaaaa" + UUID().uuidString
        let scopeB = "https://b.reception.test|app_bbbbbbbbbbbbbbbbbbbbbb" + UUID().uuidString
        // The same selection `Reception.configure` makes for a scope.
        func store(_ scope: String) -> DeviceStore { DeviceStore(scope: scope + DeviceStore.generation(for: scope)) }
        let api = ReceptionAPI(appId: "app_abcdefghijklmnopqrstuv", baseURL: try XCTUnwrap(URL(string: "https://reception.test")))

        let first = DeviceSession(api: api, store: store(scopeA), now: { [time] in time.now })
        first.cooldowns.impose(.messages, seconds: 7200)
        first.deactivate()
        let other = DeviceSession(api: api, store: store(scopeB), now: { [time] in time.now })
        XCTAssertNil(other.cooldowns.blocking(RetryScope.allCases))
        other.deactivate()
        let returned = DeviceSession(api: api, store: store(scopeA), now: { [time] in time.now })
        XCTAssertEqual(returned.cooldowns.blocking([.messages])?.until, time.now.addingTimeInterval(7200))
        returned.deactivate()
    }

    func testStoredWaitsAreBoundedByOneDayAndExpire() throws {
        let scope = "bounded-" + UUID().uuidString
        let store = DeviceStore(scope: scope)
        store.cooldowns = [
            .init(scope: .messages, until: time.now.addingTimeInterval(10 * 86_400), automatic: false),
            .init(scope: .uploads, until: time.now.addingTimeInterval(-1), automatic: true)
        ]
        let api = ReceptionAPI(appId: "app_abcdefghijklmnopqrstuv", baseURL: try XCTUnwrap(URL(string: "https://reception.test")))
        let session = DeviceSession(api: api, store: store, now: { [time] in time.now })
        defer { session.invalidate() }

        XCTAssertEqual(session.cooldowns.blocking([.messages])?.until, time.now.addingTimeInterval(86_400))
        XCTAssertEqual(session.cooldowns.active[.messages]?.until, time.now.addingTimeInterval(86_400))
        time.now.addTimeInterval(86_400)
        XCTAssertNil(session.cooldowns.blocking([.messages]))
        XCTAssertNil(session.cooldowns.blocking([.uploads]))
        time.now.addTimeInterval(86_400)
        XCTAssertNil(session.cooldowns.blocking([.messages]))
    }

    func testLongerWaitDecidesAndShortWaitsNeverShortenIt() throws {
        let session = try makeSession { _ in StubURLProtocol.Reply() }
        defer { finish(session) }
        session.cooldowns.impose(.messages, seconds: 3600)
        session.cooldowns.impose(.messages, seconds: 5)
        XCTAssertEqual(session.cooldowns.blocking([.messages])?.until, time.now.addingTimeInterval(3600))

        time.now.addTimeInterval(3570)
        XCTAssertEqual(session.cooldowns.blocking([.messages])?.automatic, false,
                       "A long wait that is nearly over still needs a manual retry")
        session.cooldowns.impose(.requests, seconds: 50)
        XCTAssertEqual(session.cooldowns.blocking([.messages, .requests])?.automatic, false)
        XCTAssertEqual(session.cooldowns.blocking([.messages, .requests])?.scope, .requests)
    }

    func testTheSameWaitIsRecordedOnceAndChangesAreAnnounced() throws {
        let session = try makeSession { _ in StubURLProtocol.Reply() }
        defer { finish(session) }
        var changes = 0
        session.cooldowns.onChange = { changes += 1 }
        session.cooldowns.impose(.session, seconds: 300)
        let deadline = session.cooldowns.blocking([.session])?.until

        // A renewal limit reaches the renewal and the request that waited for it.
        time.now.addTimeInterval(0.4)
        session.cooldowns.impose(.session, seconds: 300)

        XCTAssertEqual(changes, 1)
        XCTAssertEqual(session.cooldowns.blocking([.session])?.until, deadline)
    }

    func testTheEndOfAWaitIsAnnouncedByItsTimer() async throws {
        let api = ReceptionAPI(appId: "app_abcdefghijklmnopqrstuv", baseURL: try XCTUnwrap(URL(string: "https://reception.test")))
        let session = DeviceSession(api: api, store: DeviceStore(scope: "expiry-" + UUID().uuidString))
        defer { session.invalidate() }
        let ended = expectation(description: "End of the wait announced")
        session.cooldowns.onChange = { if session.cooldowns.blocking([.uploads]) == nil { ended.fulfill() } }
        session.cooldowns.impose(.uploads, seconds: 1)

        await fulfillment(of: [ended], timeout: 3)
        XCTAssertTrue(session.cooldowns.active.isEmpty)
    }

    func testAClockSetBackCannotStretchARunningWait() throws {
        let session = try makeSession { _ in StubURLProtocol.Reply() }
        defer { finish(session) }
        session.cooldowns.impose(.messages, seconds: 30)
        time.now.addTimeInterval(-2 * 86_400)

        XCTAssertEqual(session.cooldowns.blocking([.messages])?.until, time.now.addingTimeInterval(86_400))
    }

    func testLocalRejectionsNeverSpendTheRetryBudgetAndForegroundKeepsTheGate() async throws {
        let session = try makeSession { _ in Self.limited("messages", seconds: 30) }
        defer { finish(session) }
        var state = RetryState()
        do { try await post(session, "conversation/messages") } catch { state.failed(error) }
        XCTAssertEqual(state.attempts, 1)

        for _ in 0..<20 {
            do { try await post(session, "conversation/messages") } catch { state.failed(error) }
        }
        XCTAssertEqual(state.attempts, 1, "Rejections without a network attempt cost nothing")
        XCTAssertFalse(state.stopped)
        XCTAssertNotNil(state.delay)

        state.foreground()
        await expectCooldown(.messages) { try await self.post(session, "conversation/messages") }
        XCTAssertEqual(StubURLProtocol.requests.count, 1)
    }
}
