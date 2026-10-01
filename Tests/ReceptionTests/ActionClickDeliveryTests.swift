import XCTest
@testable import Reception

final class ActionClickDeliveryTests: XCTestCase {
    @MainActor
    func testQueuePersistsDeduplicatesAndResets() throws {
        let scope = UUID().uuidString
        let store = DeviceStore(scope: scope, credentialStorage: .init(read: { _ in .missing }, save: { _, _ in true }, delete: { _ in true }))
        let session = DeviceSession(api: ReceptionAPI(appId: "app_abcdefghijklmnopqrstuv", baseURL: try XCTUnwrap(URL(string: "https://example.invalid"))), store: store)
        defer { session.invalidate() }
        session.recordActionClick("review")
        session.recordActionClick("paywall")
        session.recordActionClick("paywall")
        XCTAssertEqual(DeviceStore(scope: scope, credentialStorage: .init(read: { _ in .missing }, save: { _, _ in true }, delete: { _ in true })).pendingActionClicks, ["review", "paywall"])
        store.resetChat(revision: 2)
        XCTAssertTrue(store.pendingActionClicks.isEmpty)
        session.recordActionClick("obsolete")
        XCTAssertTrue(store.pendingActionClicks.isEmpty)
    }

    @MainActor
    func testDeliveryUsesSharedEndpointAndRetriesTransientFailures() async throws {
        ActionClickProtocol.failures.reset()
        XCTAssertTrue(URLProtocol.registerClass(ActionClickProtocol.self))
        defer { URLProtocol.unregisterClass(ActionClickProtocol.self) }
        let store = DeviceStore(scope: UUID().uuidString, credentialStorage: .init(read: { _ in .missing }, save: { _, _ in true }, delete: { _ in true }))
        store.chatRevision = 7
        store.hasStartedChat = true
        let session = DeviceSession(api: ReceptionAPI(appId: "app_abcdefghijklmnopqrstuv", baseURL: try XCTUnwrap(URL(string: "https://action-click.test"))), store: store)
        defer { session.invalidate() }
        _ = try await RequestContext.$probe.withValue(RequestProbe()) { try await session.token() }
        XCTAssertEqual(session.accessToken, "test-token")
        XCTAssertEqual(session.credentials?.sessionSecret, "test-secret")
        for id in ["review", "paywall", "missing"] {
            session.recordActionClick(id)
            await session.actionClickTask?.value
            XCTAssertTrue(store.pendingActionClicks.isEmpty)
        }
        session.recordActionClick("transient")
        await session.actionClickTask?.value
        XCTAssertEqual(store.pendingActionClicks, ["transient"])
        XCTAssertNotNil(session.retries["action:transient"]?.delay)
        session.flushActionClicks()
        await session.actionClickTask?.value
        XCTAssertTrue(store.pendingActionClicks.isEmpty)
        session.deactivate()
        session.recordActionClick("ignored")
        XCTAssertTrue(store.pendingActionClicks.isEmpty)
    }
    @MainActor
    func testActionReceiptRenewsRejectedAccessWithoutRegisteringAgain() async throws {
        StubURLProtocol.install { request in
            if request.path == "/v1/devices/me/token" {
                return .init(body: #"{"token":"fresh"}"#)
            }
            return request.authorization == "Bearer fresh" ? .init() :
                .init(status: 401, body: #"{"error":{"code":"unauthorized","message":"Expired"}}"#)
        }
        let store = DeviceStore(scope: UUID().uuidString, credentialStorage: .init(
            read: { _ in .missing }, save: { _, _ in true }, delete: { _ in true }))
        store.hasStartedChat = true
        let session = DeviceSession(api: ReceptionAPI(appId: "app_abcdefghijklmnopqrstuv",
            baseURL: try XCTUnwrap(URL(string: "https://reception.test"))), store: store)
        session.credentials = SessionCredentials(sessionSecret: "same-secret", verifiedUserId: nil)
        session.accessToken = "expired"
        defer { session.invalidate(); StubURLProtocol.uninstall() }

        session.recordActionClick("paywall")
        await session.actionClickTask?.value

        XCTAssertTrue(store.pendingActionClicks.isEmpty)
        XCTAssertEqual(StubURLProtocol.requests.map(\.path), [
            "/v1/conversation/action-click", "/v1/devices/me/token", "/v1/conversation/action-click"])
        XCTAssertEqual(StubURLProtocol.requests.map(\.authorization), ["Bearer expired", nil, "Bearer fresh"])
        let refreshBody = try XCTUnwrap(StubURLProtocol.requests[1].body)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: refreshBody) as? [String: String],
                       ["sessionSecret": "same-secret"])
        XCTAssertEqual(StubURLProtocol.requests.first?.body, StubURLProtocol.requests.last?.body)
        XCTAssertEqual(session.credentials?.sessionSecret, "same-secret")
    }

}

private final class ActionClickProtocol: URLProtocol, @unchecked Sendable {
    static let failures = DeliveryFailures()
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "action-click.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if request.url?.path == "/v1/devices" {
            respond(status: 201, body: "{\"token\":\"test-token\",\"sessionSecret\":\"test-secret\",\"verifiedUserId\":null}")
            return
        }
        XCTAssertEqual(request.url?.path, "/v1/conversation/action-click")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-App-Id"), "app_abcdefghijklmnopqrstuv")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Reception-Revision"), "7")
        var data = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(contentsOf: buffer.prefix(count))
            }
        }
        let body = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        XCTAssertEqual(body?.count, 1)
        let id = body?["messageId"]
        XCTAssertNotNil(id)
        let status = id == "transient" && Self.failures.consume() ? 503 : id == "missing" ? 404 : 200
        respond(status: status, body: status == 200 ? "{}" : "{\"error\":{\"code\":\"\(status == 404 ? "action_not_found" : "unavailable")\",\"message\":\"Unavailable\"}}")
    }
    private func respond(status: Int, body: String) {
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil) else {
            XCTFail("Invalid stub response")
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class DeliveryFailures: @unchecked Sendable {
    private let lock = NSLock()
    private var remaining = 1

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        remaining = 1
    }

    func consume() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard remaining > 0 else { return false }
        remaining -= 1
        return true
    }
}
