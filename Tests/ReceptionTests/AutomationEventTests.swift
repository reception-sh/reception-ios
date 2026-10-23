import XCTest
@testable import Reception

/// `track` must never surprise an app: events stay on the device unless an enabled automation listens, an older
/// service without automations changes nothing, and a listened event registers the device and goes out once.
@MainActor
final class AutomationEventTests: XCTestCase {
    private var session: DeviceSession?

    override func tearDown() {
        session?.invalidate()
        Reception.shared.session = nil
        StubURLProtocol.uninstall()
        super.tearDown()
    }

    private func start(_ responder: @escaping StubURLProtocol.Responder) throws -> DeviceSession {
        StubURLProtocol.install(responder)
        var values: [String: String] = [:]
        let storage = DeviceStore.CredentialStorage(
            read: { values[$0].map(KeychainStore.ReadResult.value) ?? .missing },
            save: { values[$1] = $0; return true },
            delete: { values.removeValue(forKey: $0); return true })
        let store = DeviceStore(scope: "automation-events-" + UUID().uuidString, credentialStorage: storage)
        // The listing of listened events is cached per app ID, so each test gets its own.
        let appId = "app_" + String(UUID().uuidString.filter(\.isLetter).prefix(22)).padding(toLength: 22, withPad: "x", startingAt: 0)
        let api = ReceptionAPI(appId: appId, baseURL: try XCTUnwrap(URL(string: "https://reception.test")))
        let session = DeviceSession(api: api, store: store)
        self.session = session
        // The automation checks that it still serves the active session before it trusts a reply.
        Reception.shared.session = session
        return session
    }

    /// Requests are made in the background; a wait lets every request of a tracked event arrive, or shows none came.
    private func settle(_ seconds: Double = 0.6) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    private var paths: [String] { StubURLProtocol.requests.map(\.path) }

    func testEventStaysOnTheDeviceWhenNoAutomationListens() async throws {
        let session = try start { request in
            request.path == "/v1/automations" ? .init(body: #"{"events":["checkout_cancelled"]}"#) : .init(status: 404)
        }
        Reception.shared.automations.track("paywall_declined", opensChat: true, session: session)
        await settle()
        XCTAssertEqual(paths, ["/v1/automations"], "An unheard event never registers the device or leaves it")
        XCTAssertFalse(session.isRegistered)
        XCTAssertFalse(session.store.hasStartedChat)
    }

    func testAServiceWithoutAutomationsChangesNothing() async throws {
        let session = try start { _ in .init(status: 404, body: #"{"error":{"code":"not_found","message":"No"}}"#) }
        Reception.shared.automations.track("paywall_declined", opensChat: true, session: session)
        await settle()
        Reception.shared.automations.track("paywall_declined", opensChat: true, session: session)
        await settle()
        XCTAssertEqual(paths, ["/v1/automations"], "One failed listing holds events back for a while instead of retrying each time")
        XCTAssertFalse(session.isRegistered)
    }

    func testAListenedEventRegistersTheDeviceAndIsSentOnce() async throws {
        let session = try start { request in
            switch (request.method, request.path) {
            case ("GET", "/v1/automations"): return .init(body: #"{"events":["paywall_declined"]}"#)
            case ("POST", "/v1/devices"): return .init(body: #"{"token":"automation-token","sessionSecret":"automation-secret","verifiedUserId":null}"#)
            // A newer service may add fields; the SDK reads only what it knows.
            case ("POST", "/v1/automations/events"): return .init(body: #"{"sent":true,"scheduled":false,"openChat":false,"later":{"minutes":5}}"#)
            default: return .init(body: "{}")
            }
        }
        Reception.shared.automations.track("paywall_declined", opensChat: false, session: session)
        await settle(1.5)
        XCTAssertEqual(paths.filter { $0 == "/v1/automations/events" }.count, 1)
        XCTAssertTrue(session.isRegistered, "The event registers a device that never wrote")
        let event = try XCTUnwrap(StubURLProtocol.requests.first { $0.path == "/v1/automations/events" })
        XCTAssertEqual(event.authorization, "Bearer automation-token")
        XCTAssertEqual(try JSONSerialization.jsonObject(with: XCTUnwrap(event.body)) as? [String: String], ["event": "paywall_declined"])
        XCTAssertTrue(session.store.hasStartedChat, "The message is in the chat now, so the chat watches for replies")
    }

    func testTheListingIsSharedAcrossEventsAndMalformedNamesNeverLeave() async throws {
        let session = try start { request in
            request.path == "/v1/automations" ? .init(body: #"{"events":[]}"#) : .init(status: 404)
        }
        for event in ["paywall_declined", "checkout_cancelled", "onboarding_completed"] {
            Reception.shared.automations.track(event, opensChat: true, session: session)
        }
        await settle()
        XCTAssertEqual(paths, ["/v1/automations"], "One listing answers for every event")
        XCTAssertFalse(Automations.accepts("paywall declined"))
    }
}
