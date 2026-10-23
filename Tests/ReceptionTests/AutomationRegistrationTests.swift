import XCTest
@testable import Reception

@MainActor
final class AutomationRegistrationTests: XCTestCase {
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
        let store = DeviceStore(scope: "automation-tests-" + UUID().uuidString, credentialStorage: storage)
        let api = ReceptionAPI(appId: "app_abcdefghijklmnopqrstuv", baseURL: try XCTUnwrap(URL(string: "https://reception.test")))
        return DeviceSession(api: api, store: store)
    }

    func testOnlyAnAutomationEventRegistersBeforeTheUserWrites() async throws {
        StubURLProtocol.install { request in
            request.method == "POST" && request.path == "/v1/devices"
                ? .init(body: #"{"token":"automation-token","sessionSecret":"automation-secret","verifiedUserId":null}"#)
                : .init(status: 404)
        }
        let session = try makeSession()
        defer { session.invalidate() }

        do {
            _ = try await session.token()
            XCTFail("Without a user send or an automation event, no device may be registered")
        } catch let error as ReceptionAPIError {
            XCTAssertEqual(error.code, "chat_not_started")
        }
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)

        let token = try await RequestContext.$automation.withValue(true) { try await session.token() }

        XCTAssertEqual(token, "automation-token")
        XCTAssertEqual(StubURLProtocol.requests.map(\.path), ["/v1/devices"])
        XCTAssertTrue(session.isRegistered)
        XCTAssertFalse(session.store.hasStartedChat, "Registering for an automation does not start the chat")
    }

    func testEventNamesFollowTheServiceRule() {
        for name in ["paywall_declined", "onboarding.step-10", String(repeating: "a", count: 64)] {
            XCTAssertTrue(Automations.accepts(name), name)
        }
        for name in ["", "paywall declined", "größe", String(repeating: "a", count: 65), "a\nb"] {
            XCTAssertFalse(Automations.accepts(name), name)
        }
    }
}
