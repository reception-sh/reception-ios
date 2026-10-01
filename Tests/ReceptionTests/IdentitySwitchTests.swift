import XCTest
@testable import Reception

@MainActor
final class IdentitySwitchTests: XCTestCase {
    private let reception = Reception.shared

    private func token(_ userId: String, signature: String = "signature") throws -> String {
        let payload = try JSONSerialization.data(withJSONObject: ["user_id": userId])
            .base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return "e30.\(payload).\(signature)"
    }

    private func prepare(registered: Bool) throws -> DeviceSession {
        reception.usesRemoteAppearance = false
        reception.updatesAppBadge = false
        let baseURL = try XCTUnwrap(URL(string: "https://reception.test/" + UUID().uuidString))
        // Package tests have no app bundle for notification APIs; seed configuration without starting its lifecycle.
        reception.scope = "app_abcdefghijklmnopqrstuv"
        reception.unreadMonitor.setActive(false)
        reception.session?.deactivate()
        var saved: String?
        let storage = DeviceStore.CredentialStorage(
            read: { _ in saved.map(KeychainStore.ReadResult.value) ?? .missing },
            save: { value, _ in saved = value; return true },
            delete: { _ in saved = nil; return true })
        let store = DeviceStore(scope: "switch-tests-" + UUID().uuidString, credentialStorage: storage)
        store.hasStartedChat = true
        store.hasConversation = registered
        store.draftText = "Old draft"
        store.pending = DeviceIdentity(name: "Old name", email: "old@example.test", metadata: ["old": "value"],
                                       pushToken: "test-push", pushEnvironment: "sandbox")
        let session = DeviceSession(api: ReceptionAPI(appId: "app_abcdefghijklmnopqrstuv", baseURL: baseURL), store: store)
        if registered {
            try store.save(SessionCredentials(sessionSecret: "old-secret", verifiedUserId: nil))
            _ = try session.storedCredentials()
            session.accessToken = "old-access"
        }
        session.registrationAllowed = true
        reception.session = session
        return session
    }

    private func finish(_ session: DeviceSession) {
        reception.onEvent = nil
        reception.session?.invalidate()
        session.invalidate()
        reception.session = nil
        reception.scope = nil
        reception.forgetIdentityToken()
        reception.updatesAppBadge = true
        reception.usesRemoteAppearance = true
        StubURLProtocol.uninstall()
    }

    func testUserSwitchDuringRegistrationCancelsOldSendAndKeepsNewRegistrationLazy() async throws {
        try await checkSwitchDuringRequest(registered: false)
    }

    func testUserSwitchDuringVerificationPatchCancelsOldSendAndClearsChat() async throws {
        try await checkSwitchDuringRequest(registered: true)
    }

    private func checkSwitchDuringRequest(registered: Bool) async throws {
        let gate = StubURLProtocol.Gate()
        let started = expectation(description: "Identity request started")
        StubURLProtocol.install { request in
            let expected = registered ? request.method == "PATCH" : request.path.hasSuffix("/v1/devices")
            if expected {
                started.fulfill()
                return StubURLProtocol.Reply(status: registered ? 200 : 201,
                    body: registered ? #"{"verifiedUserId":"A"}"#
                        : #"{"token":"late-A","sessionSecret":"secret-A","verifiedUserId":"A"}"#, gate: gate)
            }
            return StubURLProtocol.Reply()
        }
        let original = try prepare(registered: registered)
        defer { gate.release(); finish(original) }
        reception.identify(token: try token("A"))
        let sending = Task {
            if registered { try await original.update() }
            let _: EmptyResponse = try await original.api.request("conversation/messages", method: "POST", authenticated: true)
        }
        await fulfillment(of: [started], timeout: 3)
        let nextToken = try token("B")

        reception.identify(token: nextToken)

        XCTAssertTrue(original.invalidated, "The previous identity must be isolated synchronously")
        let replacement = try XCTUnwrap(reception.session)
        XCTAssertFalse(replacement === original)
        XCTAssertNil(replacement.credentials)
        XCTAssertNil(replacement.registration)
        XCTAssertFalse(replacement.registrationAllowed)
        XCTAssertFalse(replacement.store.hasConversation)
        XCTAssertTrue(replacement.store.draftText.isEmpty)
        XCTAssertNil(replacement.store.pending.externalUserId)
        XCTAssertNil(replacement.store.pending.name)
        XCTAssertNil(replacement.store.pending.email)
        XCTAssertTrue(replacement.store.pending.metadata.isEmpty)
        XCTAssertEqual(replacement.store.pending.pushToken, "test-push")
        XCTAssertEqual(replacement.store.pending.pushEnvironment, "sandbox")
        XCTAssertEqual(reception.identityToken?.value, nextToken)
        XCTAssertEqual(reception.identityToken?.sent, false)
        gate.release()
        let result = await sending.result
        XCTAssertThrowsError(try result.get())
        XCTAssertNil(original.credentials?.verifiedUserId)
        XCTAssertNil(replacement.credentials)
        XCTAssertEqual(reception.identityToken?.value, nextToken)
        XCTAssertFalse(StubURLProtocol.requests.contains { $0.path.hasSuffix("/conversation/messages") })
        XCTAssertEqual(StubURLProtocol.requests.filter { $0.path.hasSuffix("/v1/devices") }.count, registered ? 0 : 1)

        let stale = try XCTUnwrap(IdentityToken(token("A")))
        var rejected = false
        reception.onEvent = { if case .identityRejected = $0 { rejected = true } }
        original.identityRejected(stale, ReceptionAPIError(code: "identity_mismatch", status: 409))
        original.identityRejected(stale, ReceptionAPIError(code: "identity_token_expired", status: 401))
        XCTAssertTrue(reception.session === replacement)
        XCTAssertEqual(reception.identityToken?.value, nextToken)
        XCTAssertFalse(rejected)
    }

    func testSupersededMismatchCannotRestoreOldToken() async throws {
        try await checkSupersededError(code: "identity_mismatch", status: 409)
    }

    func testSupersededRejectionDoesNotNotifyOrDropLatestToken() async throws {
        try await checkSupersededError(code: "identity_token_expired", status: 401)
    }

    func testCurrentTokenRejectionStillDropsTokenAndNotifiesHost() throws {
        let session = try prepare(registered: true)
        defer { finish(session) }
        reception.identify(token: try token("A"))
        let currentToken = try XCTUnwrap(reception.identityToken)
        var events: [ReceptionEvent] = []
        reception.onEvent = { events.append($0) }

        session.identityRejected(currentToken, ReceptionAPIError(code: "identity_token_expired", status: 401))

        XCTAssertNil(reception.identityToken)
        XCTAssertEqual(events, [.identityRejected(ReceptionError(code: "identity_token_expired", status: 401))])
        XCTAssertTrue(reception.session === session)
    }

    private func checkSupersededError(code: String, status: Int) async throws {
        let gate = StubURLProtocol.Gate()
        let started = expectation(description: "Old token PATCH started")
        let oldToken = try token("A", signature: "old")
        StubURLProtocol.install { request in
            if request.method == "PATCH", let body = request.body,
               let values = try? JSONSerialization.jsonObject(with: body) as? [String: Any], values["identityToken"] as? String == oldToken {
                started.fulfill()
                return StubURLProtocol.Reply(status: status, body: #"{"error":{"code":"\#(code)","message":"Rejected"}}"#, gate: gate)
            }
            return StubURLProtocol.Reply(body: #"{"verifiedUserId":null}"#)
        }
        let original = try prepare(registered: true)
        defer { gate.release(); finish(original) }
        reception.identify(token: oldToken)
        var rejections = 0
        reception.onEvent = { if case .identityRejected = $0 { rejections += 1 } }
        let updating = Task { try await original.update() }
        await fulfillment(of: [started], timeout: 3)
        let latestToken = try token("A", signature: "new")
        reception.identify(token: latestToken)
        XCTAssertTrue(reception.session === original, "A fresh token for the identical user preserves the session")

        gate.release()
        try await updating.value

        XCTAssertTrue(reception.session === original)
        XCTAssertFalse(original.invalidated)
        XCTAssertEqual(reception.identityToken?.value, latestToken)
        XCTAssertEqual(reception.identityToken?.sent, false)
        XCTAssertEqual(rejections, 0)
    }
}
