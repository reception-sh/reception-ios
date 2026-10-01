import XCTest
@testable import Reception

@MainActor
final class SubmissionRecoveryTests: XCTestCase {
    static func restart(_ f: LimitReleaseFixture, registered: Bool = true) -> ChatModel {
        f.chat.stopPolling()
        f.session.deactivate()
        let session = DeviceSession(api: f.session.api, store: f.session.store)
        if registered {
            session.credentials = SessionCredentials(sessionSecret: "secret", verifiedUserId: nil)
            session.accessToken = "access"
        }
        Reception.shared.session = session
        let chat = ChatModel(session: session)
        chat.isVisible = true
        session.cooldowns.onChange = { [weak chat] in chat?.cooldownsChanged() }
        return chat
    }

    static func failedSend(_ f: LimitReleaseFixture, reply: StubURLProtocol.Reply) async {
        f.chat.isVisible = false
        f.script.state.withLock { $0.sends = [reply] }
        let id = UUID().uuidString
        f.chat.messages.append(Message(id: id, sender: "USER", text: "submitted", attachments: [], createdAt: Date(), status: .sending))
        f.chat.saveMessages()
        f.chat.submit(id, userInitiated: true)
        await f.chat.sends[id]?.value
    }

    func testTransportFailureRestoresFreshSessionAndOriginalIDWithoutSendingDraft() async throws {
        let f = try LimitReleaseFixture()
        defer { f.finish() }
        await Self.failedSend(f, reply: .init(networkError: .notConnectedToInternet))
        let id = try XCTUnwrap(f.chat.messages.first?.id)
        XCTAssertTrue(f.chat.messages[0].retryAfterTransientFailure)
        let chat = Self.restart(f)
        defer { chat.stopPolling(); chat.session?.deactivate() }
        chat.composer.text = "Unsubmitted draft"
        XCTAssertTrue(chat.session?.retries.isEmpty == true)
        await chat.load(recheckLimits: true)
        try await f.waitUntil { chat.messages.first?.status == .sent }
        XCTAssertEqual(f.posts, [id, id])
        XCTAssertEqual(chat.composer.text, "Unsubmitted draft")
        XCTAssertFalse(chat.messages[0].retryAfterTransientFailure)
    }

    func testLostResponseMergesBeforeRetryIncludingInterruptedPending() async throws {
        for pending in [false, true] {
            let f = try LimitReleaseFixture()
            await Self.failedSend(f, reply: .init(networkError: .networkConnectionLost))
            let id = try XCTUnwrap(f.chat.messages.first?.id)
            if pending { f.chat.messages[0].status = .sending; f.chat.saveMessages() }
            f.script.state.withLock {
                $0.conversation = .init(body: "{\"conversation\":null,\"messages\":[\(LimitReleaseFixture.Script.message(id, seq: 1))]}")
            }
            let chat = Self.restart(f)
            await chat.load(recheckLimits: true)
            XCTAssertEqual(chat.messages.first?.status, .sent)
            XCTAssertEqual(f.posts, [id])
            chat.stopPolling(); chat.session?.deactivate(); f.finish()
        }
    }

    func testPermanentCancelledAndLegacyFailuresNeverResume() async throws {
        for reply in [StubURLProtocol.Reply(status: 400, body: #"{"error":{"code":"invalid_message","message":"Invalid"}}"#),
                      .init(networkError: .cancelled)] {
            let f = try LimitReleaseFixture()
            await Self.failedSend(f, reply: reply)
            XCTAssertFalse(f.chat.messages[0].retryAfterTransientFailure)
            f.held("legacy", eligible: false)
            let chat = Self.restart(f)
            await chat.load(recheckLimits: true)
            XCTAssertEqual(f.posts.count, 1)
            XCTAssertTrue(chat.session?.retries.isEmpty == true)
            chat.stopPolling(); chat.session?.deactivate(); f.finish()
        }
    }

    func testExplicitCancelSurvivesRestartAndCancelsLaterRecoveries() async throws {
        let f = try LimitReleaseFixture()
        defer { f.finish() }
        await Self.failedSend(f, reply: .init(networkError: .notConnectedToInternet))
        await Self.failedSend(f, reply: .init(networkError: .notConnectedToInternet))
        f.chat.cancelAutomaticRetry(messageId: f.chat.messages[0].id)
        let chat = Self.restart(f)
        defer { chat.stopPolling(); chat.session?.deactivate() }
        await chat.load(recheckLimits: true)
        XCTAssertEqual(f.posts.count, 2)
        XCTAssertTrue(chat.messages.allSatisfy { !$0.retryAfterTransientFailure && $0.awaitsManualRetry })
    }

    func testReopeningDoesNotRenewSpentRetryBudget() async throws {
        let f = try LimitReleaseFixture()
        defer { f.finish() }
        await Self.failedSend(f, reply: .init(networkError: .notConnectedToInternet))
        let chat = Self.restart(f)
        defer { chat.stopPolling(); chat.session?.deactivate() }
        let id = chat.messages[0].id
        var retry = RetryState()
        for _ in 0..<8 { retry.failed(URLError(.notConnectedToInternet)) }
        chat.session?.retries[id] = retry
        await chat.load(recheckLimits: true)
        await chat.load(recheckLimits: true)
        XCTAssertEqual(chat.session?.retries[id]?.attempts, 8)
        XCTAssertEqual(chat.session?.retries[id]?.stopped, true)
        XCTAssertEqual(f.posts.count, 1)
    }

    func testFirstEverOfflineSubmissionCanRegisterAfterRestart() async throws {
        let f = try LimitReleaseFixture()
        defer { f.finish() }
        f.session.credentials = nil; f.session.accessToken = nil
        f.chat.isVisible = false
        StubURLProtocol.install { _ in .init(networkError: .notConnectedToInternet) }
        let id = UUID().uuidString
        f.chat.messages.append(Message(id: id, sender: "USER", text: "first submission", attachments: [], createdAt: Date(), status: .sending))
        f.chat.saveMessages()
        f.chat.submit(id, userInitiated: true)
        await f.chat.sends[id]?.value
        let chat = Self.restart(f, registered: false)
        defer { chat.stopPolling(); chat.session?.deactivate() }
        StubURLProtocol.install { [script = f.script] request in
            if request.path == "/v1/devices" {
                return .init(body: #"{"token":"access","sessionSecret":"secret","verifiedUserId":null}"#)
            }
            return script.reply(request)
        }
        await chat.load(recheckLimits: true)
        try await f.waitUntil { chat.messages.first?.status == .sent }
        XCTAssertEqual(f.posts, [id])
        XCTAssertEqual(StubURLProtocol.requests.filter { $0.path == "/v1/devices" }.count, 1)
        XCTAssertFalse(StubURLProtocol.requests.contains { $0.path == "/v1/conversation" })
    }

    func testOfflineOpeningSeedsBoundedRetryAfterFailedHistoryRead() async throws {
        let f = try LimitReleaseFixture()
        defer { f.finish() }
        await Self.failedSend(f, reply: .init(networkError: .notConnectedToInternet))
        f.script.state.withLock { $0.conversation = .init(networkError: .notConnectedToInternet) }
        let chat = Self.restart(f)
        defer { chat.stopPolling(); chat.session?.deactivate() }
        await chat.load(recheckLimits: true)
        try await f.waitUntil { chat.messages.first?.status == .sent }
        XCTAssertEqual(f.posts.count, 2)
    }

    func testPermissionAndCooldownPreventRestoredSubmission() async throws {
        for device in [#"{"blocked":true,"verificationRequired":false}"#,
                       #"{"blocked":false,"verificationRequired":true}"#] {
            let f = try LimitReleaseFixture()
            await Self.failedSend(f, reply: .init(networkError: .notConnectedToInternet))
            f.script.state.withLock { $0.conversation = .init(body: "{\"conversation\":null,\"messages\":[],\"device\":\(device)}") }
            let chat = Self.restart(f)
            await chat.load(recheckLimits: true)
            XCTAssertEqual(f.posts.count, 1)
            XCTAssertTrue(chat.session?.retries.isEmpty == true)
            chat.stopPolling(); chat.session?.deactivate(); f.finish()
        }
        let f = try LimitReleaseFixture()
        defer { f.finish() }
        await Self.failedSend(f, reply: .init(networkError: .notConnectedToInternet))
        let chat = Self.restart(f)
        defer { chat.stopPolling(); chat.session?.deactivate() }
        chat.session?.cooldowns.impose(.messages, seconds: 3600)
        f.script.state.withLock { $0.conversation = .init(body: #"{"conversation":null,"messages":[]}"#) }
        await chat.load(recheckLimits: true)
        XCTAssertEqual(f.posts.count, 1)
        XCTAssertNil(chat.session?.retries[chat.messages[0].id])
    }
}
