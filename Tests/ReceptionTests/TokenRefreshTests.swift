import XCTest
@testable import Reception

private enum Replies {
    static let unauthorized = StubURLProtocol.Reply(status: 401,
        body: #"{"error":{"code":"unauthorized","message":"Unauthorized."}}"#)
    static let revoked = StubURLProtocol.Reply(status: 401,
        body: #"{"error":{"code":"session_revoked","message":"Session revoked."}}"#)
    static func token(_ value: String, delay: TimeInterval = 0) -> StubURLProtocol.Reply {
        StubURLProtocol.Reply(body: #"{"token":"\#(value)"}"#, delay: delay)
    }
}

/// Sessions use memory credentials and injected storage, without requiring Keychain entitlements.
@MainActor
final class TokenRefreshTests: XCTestCase {
    private func makeSession(_ responder: @escaping StubURLProtocol.Responder) throws -> DeviceSession {
        StubURLProtocol.install(responder)
        let store = DeviceStore(scope: "tests-" + UUID().uuidString, credentialStorage: .init(
            read: { _ in .missing }, save: { _, _ in true }, delete: { _ in true }))
        store.hasStartedChat = true
        let baseURL = try XCTUnwrap(URL(string: "https://reception.test"))
        let session = DeviceSession(api: ReceptionAPI(appId: "app_abcdefghijklmnopqrstuv", baseURL: baseURL), store: store)
        session.credentials = SessionCredentials(sessionSecret: "secret-1", verifiedUserId: nil)
        return session
    }

    private func finish(_ session: DeviceSession) {
        session.invalidate()
        StubURLProtocol.uninstall()
    }

    private func loadUnread(_ session: DeviceSession) async throws {
        let _: EmptyResponse = try await session.api.request("conversation/unread", authenticated: true)
    }

    private var paths: [String] { StubURLProtocol.requests.map(\.path) }

    func testRequestsWithoutTokenShareOneRefresh() async throws {
        let session = try makeSession { request in
            if request.path == "/v1/devices/me/token" { return Replies.token("fresh", delay: 0.1) }
            return request.authorization == "Bearer fresh" ? StubURLProtocol.Reply() : Replies.unauthorized
        }
        defer { finish(session) }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<5 { group.addTask { try await self.loadUnread(session) } }
            try await group.waitForAll()
        }

        let refreshes = StubURLProtocol.requests.filter { $0.path == "/v1/devices/me/token" }
        XCTAssertEqual(refreshes.count, 1)
        XCTAssertNil(refreshes.first?.authorization)
        let body = try XCTUnwrap(refreshes.first?.body)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: body) as? [String: String], ["sessionSecret": "secret-1"])
        XCTAssertEqual(StubURLProtocol.requests.filter { $0.path == "/v1/conversation/unread" }.map(\.authorization),
                       Array(repeating: "Bearer fresh", count: 5))
        XCTAssertEqual(session.accessToken, "fresh")
    }

    func testRejectedTokenIsRefreshedAndRetriedOnce() async throws {
        let session = try makeSession { request in
            if request.path == "/v1/devices/me/token" { return Replies.token("fresh") }
            return request.authorization == "Bearer fresh" ? StubURLProtocol.Reply() : Replies.unauthorized
        }
        defer { finish(session) }
        session.accessToken = "stale"

        try await loadUnread(session)

        XCTAssertEqual(paths, ["/v1/conversation/unread", "/v1/devices/me/token", "/v1/conversation/unread"])
        XCTAssertEqual(StubURLProtocol.requests.map(\.authorization), ["Bearer stale", nil, "Bearer fresh"])
    }

    func testNewerTokenIsReusedWithoutRefresh() async throws {
        let session = try makeSession { _ in Replies.token("unexpected") }
        defer { finish(session) }
        session.accessToken = "newer"

        let token = try await session.renewedToken(replacing: "older")

        XCTAssertEqual(token, "newer")
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
    }

    func testSecondRejectionIsNotRetriedAgain() async throws {
        let session = try makeSession { request in
            request.path == "/v1/devices/me/token" ? Replies.token("fresh") : Replies.unauthorized
        }
        defer { finish(session) }
        session.accessToken = "stale"

        do {
            try await loadUnread(session)
            XCTFail("A second 401 must reach the caller")
        } catch let error as ReceptionAPIError {
            XCTAssertEqual(error.status, 401)
            XCTAssertEqual(error.code, "unauthorized")
        }
        XCTAssertEqual(paths, ["/v1/conversation/unread", "/v1/devices/me/token", "/v1/conversation/unread"])
        XCTAssertNotNil(session.credentials)
    }

    func testRevokedSessionIsForgotten() async throws {
        let session = try makeSession { _ in Replies.revoked }
        defer { finish(session) }

        do {
            try await loadUnread(session)
            XCTFail("A revoked session must fail the request")
        } catch let error as ReceptionAPIError {
            XCTAssertEqual(error.code, "session_revoked")
        }
        XCTAssertEqual(paths, ["/v1/devices/me/token"])
        XCTAssertNil(session.credentials)
        XCTAssertNil(session.accessToken)
    }

    func testDisabledAppHaltsOnRefresh() async throws {
        let session = try makeSession { _ in
            StubURLProtocol.Reply(status: 403, body: #"{"error":{"code":"app_disabled","message":"Disabled."}}"#)
        }
        defer { finish(session) }

        do {
            try await loadUnread(session)
            XCTFail("A disabled app must fail the request")
        } catch let error as ReceptionAPIError {
            XCTAssertEqual(error.code, "app_disabled")
        }
        XCTAssertEqual(session.halt, .appUnavailable)
        XCTAssertNotNil(session.credentials)
    }

    func testRefreshFinishingAfterInvalidationIsDiscarded() async throws {
        let session = try makeSession { _ in Replies.token("late", delay: 0.3) }
        defer { finish(session) }

        let refresh = Task { try await session.renewedToken(replacing: nil) }
        while StubURLProtocol.requests.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        session.deactivate()

        let result = await refresh.result
        XCTAssertThrowsError(try result.get())
        XCTAssertNil(session.accessToken)
    }
}
