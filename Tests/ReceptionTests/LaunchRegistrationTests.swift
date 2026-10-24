import XCTest
@testable import Reception

@MainActor
final class LaunchRegistrationTests: XCTestCase {
    override func tearDown() {
        StubURLProtocol.uninstall()
        super.tearDown()
    }

    private func makeSession() throws -> DeviceSession {
        var values: [String: String] = [:]
        let storage = DeviceStore.CredentialStorage(
            read: { values[$0].map(KeychainStore.ReadResult.value) ?? .missing },
            save: { values[$1] = $0; return true },
            delete: { values.removeValue(forKey: $0); return true })
        let store = DeviceStore(scope: "launch-tests-" + UUID().uuidString, credentialStorage: storage)
        let api = ReceptionAPI(appId: "app_abcdefghijklmnopqrstuv", baseURL: try XCTUnwrap(URL(string: "https://reception.test")))
        return DeviceSession(api: api, store: store)
    }

    private func waitForRequests(_ count: Int) async {
        for _ in 0..<40 where StubURLProtocol.requests.count < count { try? await Task.sleep(for: .milliseconds(50)) }
    }

    func testAnUnusedDeviceRegistersAtLaunchWithoutStartingTheChat() async throws {
        StubURLProtocol.install { request in
            request.method == "POST" && request.path == "/v1/devices"
                ? .init(status: 201, body: #"{"token":"launch-token","sessionSecret":"launch-secret","verifiedUserId":null}"#)
                : .init(status: 404)
        }
        let session = try makeSession()
        defer { session.invalidate() }

        session.registerIfNeeded()
        session.registerIfNeeded()
        await waitForRequests(1)
        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(StubURLProtocol.requests.map(\.path), ["/v1/devices"], "One registration, however often the foreground asks")
        XCTAssertTrue(session.isRegistered)
        XCTAssertFalse(session.store.hasStartedChat, "A registered device has not started a chat; the unread check decides that")
        let again = try await session.token()
        XCTAssertEqual(again, "launch-token")
    }

    func testAFailedLaunchRegistrationWaitsForTheNextForeground() async throws {
        StubURLProtocol.install { _ in .init(status: 500) }
        let session = try makeSession()
        defer { session.invalidate() }

        session.registerIfNeeded()
        await waitForRequests(1)
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(StubURLProtocol.requests.count, 1)
        XCTAssertFalse(session.isRegistered)

        session.registerIfNeeded()
        await waitForRequests(2)
        XCTAssertEqual(StubURLProtocol.requests.count, 2, "The next foreground tries again, nothing in between")
    }

    func testARegisteredDeviceThatNeverWroteStillAsksForUnread() async throws {
        let session = try makeSession()
        defer { session.invalidate() }
        XCTAssertFalse(session.isRegistered)
        do {
            _ = try await session.token()
            XCTFail("An unregistered device outside a launch asks nothing")
        } catch let error as ReceptionAPIError { XCTAssertEqual(error.code, "chat_not_started") }

        try session.store.save(SessionCredentials(sessionSecret: "stored", verifiedUserId: nil))
        session.accessToken = "stored-token"
        XCTAssertTrue(session.isRegistered)
        XCTAssertFalse(session.store.hasStartedChat)
        let again = try await session.token()
        XCTAssertEqual(again, "stored-token", "Registered devices may ask, so a conversation the team started is found")
    }

    func testAPushForThisDeviceMeansTheConversationExists() async throws {
        let reception = Reception.shared
        let previous = reception.session
        let session = try makeSession()
        reception.session = session
        defer { reception.session = previous; session.invalidate() }
        XCTAssertFalse(session.store.hasStartedChat)

        XCTAssertTrue(reception.handlePushNotification(userInfo: ["reception": ["conversationId": "thread"]], openChat: false))

        XCTAssertTrue(session.store.hasConversation)
        XCTAssertTrue(session.store.hasStartedChat, "The chat loads, polls and badges from now on")
        XCTAssertFalse(reception.handlePushNotification(userInfo: ["other": true], openChat: false))
    }
}
