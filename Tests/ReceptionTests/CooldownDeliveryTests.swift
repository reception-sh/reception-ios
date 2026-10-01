import XCTest
import os
@testable import Reception

/// Send intent under server cooldowns: short waits resend once in order, long or canceled waits need the person.
@MainActor
final class CooldownDeliveryTests: XCTestCase {
    private let reception = Reception.shared

    /// Replies per route; message and upload replies are consumed in order, then the success reply follows.
    private final class Script: Sendable {
        private let state: OSAllocatedUnfairLock<(messages: [StubURLProtocol.Reply], uploads: [StubURLProtocol.Reply], seq: Int)>
        init(messages: [StubURLProtocol.Reply] = [], uploads: [StubURLProtocol.Reply] = []) {
            state = OSAllocatedUnfairLock(initialState: (messages, uploads, 0))
        }

        func reply(_ request: StubURLProtocol.Request) -> StubURLProtocol.Reply {
            switch request.path {
            case "/v1/devices/me": return StubURLProtocol.Reply(body: #"{"verifiedUserId":null}"#)
            case "/v1/conversation/events":
                return StubURLProtocol.Reply(status: 404, body: #"{"error":{"code":"no_conversation","message":"None"}}"#)
            case "/v1/uploads":
                if let next = state.withLock({ $0.uploads.isEmpty ? nil : $0.uploads.removeFirst() }) { return next }
                return StubURLProtocol.Reply(status: 503, body: #"{"error":{"code":"uploads_unavailable","message":"Down"}}"#)
            case "/v1/conversation/messages":
                let scripted = state.withLock { state -> StubURLProtocol.Reply? in
                    state.seq += 1
                    return state.messages.isEmpty ? nil : state.messages.removeFirst()
                }
                if let scripted { return scripted }
                let clientId = request.body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["clientId"] as? String ?? ""
                let seq = state.withLock { $0.seq }
                return StubURLProtocol.Reply(status: 201, body: """
                    {"conversation":{"id":"c1","status":"OPEN","unreadForUser":0,"createdAt":"2026-09-25T10:00:00.000Z"},
                     "message":{"id":"m\(seq)","clientId":"\(clientId)","seq":\(seq),"sender":"USER","kind":"TEXT","text":"x",
                     "attachments":[],"actionClickedAt":null,"createdAt":"2026-09-25T10:00:00.000Z"}}
                    """)
            default: return StubURLProtocol.Reply()
            }
        }
    }

    nonisolated private static func limited(_ scope: String, seconds: Int) -> StubURLProtocol.Reply {
        StubURLProtocol.Reply(status: 429, body: #"{"error":{"code":"rate_limited","message":"Wait","retryScope":"\#(scope)"}}"#,
                              headers: ["Retry-After": String(seconds)])
    }

    private func prepare(_ script: Script, polling: Bool = true) throws -> (DeviceSession, ChatModel) {
        StubURLProtocol.install { script.reply($0) }
        reception.usesRemoteAppearance = false
        reception.applicationActive = true
        reception.unreadMonitor.setActive(false)
        reception.session?.deactivate()
        let store = DeviceStore(scope: "delivery-" + UUID().uuidString, credentialStorage: .init(
            read: { _ in .missing }, save: { _, _ in true }, delete: { _ in true }))
        store.hasStartedChat = true
        let api = ReceptionAPI(appId: "app_abcdefghijklmnopqrstuv", baseURL: try XCTUnwrap(URL(string: "https://reception.test")))
        let session = DeviceSession(api: api, store: store)
        session.credentials = SessionCredentials(sessionSecret: "secret", verifiedUserId: nil)
        session.accessToken = "access"
        reception.session = session
        let chat = ChatModel(session: session)
        chat.isVisible = true
        if polling { chat.startPolling() }
        return (session, chat)
    }

    private func finish(_ session: DeviceSession, _ chat: ChatModel) {
        chat.stopPolling()
        session.invalidate()
        reception.session = nil
        reception.applicationActive = false
        reception.usesRemoteAppearance = true
        StubURLProtocol.uninstall()
    }

    /// The same local steps as a composer send, without the host's notification lifecycle.
    @discardableResult
    private func send(_ chat: ChatModel, _ text: String, photos: Int = 0) async -> String {
        let images = (0..<photos).map { _ in UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { _ in } }
        let message = Message(id: UUID().uuidString, sender: "USER", text: text, attachments: [], createdAt: Date(),
                              status: .sending, images: images)
        chat.messages.append(message)
        chat.submit(message.id, userInitiated: true)
        await chat.sends[message.id]?.value
        return message.id
    }

    private func waitUntil(timeout: TimeInterval = 6, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else { return XCTFail("Condition not reached in time") }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private func message(_ chat: ChatModel, _ id: String) -> Message? { chat.messages.first { $0.id == id } }

    private var messagePosts: [String] {
        StubURLProtocol.requests.filter { $0.path == "/v1/conversation/messages" }.compactMap { request in
            request.body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["clientId"] as? String
        }
    }

    func testShortCooldownResendsQueuedMessagesOnceEachInOrder() async throws {
        let (session, chat) = try prepare(Script(messages: [Self.limited("messages", seconds: 1)]))
        defer { finish(session, chat) }
        let first = await send(chat, "First")
        let second = await send(chat, "Second")

        XCTAssertEqual(messagePosts, [first], "The second send waits for the known cooldown without a request")
        for id in [first, second] {
            XCTAssertEqual(message(chat, id)?.status, .failed, "A held message stays visibly not delivered")
            XCTAssertEqual(message(chat, id)?.awaitsManualRetry, false)
            guard case .automatic = chat.retryAvailability(for: try XCTUnwrap(message(chat, id))) else {
                return XCTFail("A short wait in a visible chat resends by itself")
            }
        }
        XCTAssertFalse(chat.cooldownAllowsSend(photos: false))
        XCTAssertEqual(chat.composerCooldown?.scope, .messages)

        try await waitUntil { chat.messages.allSatisfy { $0.status == .sent } }

        XCTAssertEqual(messagePosts, [first, first, second], "Oldest first, one at a time, same client IDs")
        XCTAssertEqual(chat.messages.count, 2, "No duplicates")
        XCTAssertEqual(chat.messages.map(\.clientId), [first, second])
    }

    func testLongCooldownNeedsManualRetryAcrossForegroundAndRestore() async throws {
        let (session, chat) = try prepare(Script(messages: [Self.limited("messages", seconds: 3600)]))
        defer { finish(session, chat) }
        let id = await send(chat, "Later")

        XCTAssertEqual(message(chat, id)?.status, .failed)
        XCTAssertEqual(message(chat, id)?.awaitsManualRetry, true)
        XCTAssertEqual(chat.retryAvailability(for: try XCTUnwrap(message(chat, id))), .waiting)
        chat.retry(messageId: id)
        session.retries[id]?.foreground()
        chat.retryFailedAutomatically()
        try await Task.sleep(for: .milliseconds(200))

        XCTAssertNil(chat.automaticRetry)
        XCTAssertEqual(messagePosts, [id], "Neither Retry nor foreground may bypass the wait")
        let restored = session.store.chatCache.load().first { $0.id == id }
        XCTAssertEqual(restored?.status, .failed)
        XCTAssertEqual(restored?.awaitsManualRetry, true, "The manual marker survives a relaunch")
        XCTAssertEqual(restored?.text, "Later")

        let reopened = ChatModel(session: session)
        reopened.isVisible = true
        reopened.startPolling()
        defer { reopened.stopPolling() }
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertNil(reopened.automaticRetry)
        XCTAssertEqual(messagePosts, [id], "A model rebuilt from the cache does not resend either")
    }

    func testCancelingAutomaticResendKeepsTheMessageUntilThePersonRetries() async throws {
        let (session, chat) = try prepare(Script(messages: [Self.limited("messages", seconds: 1)]))
        defer { finish(session, chat) }
        let id = await send(chat, "Wait for me")
        chat.cancelAutomaticRetry(messageId: id)
        try await Task.sleep(for: .milliseconds(1500))

        XCTAssertEqual(messagePosts, [id])
        XCTAssertEqual(message(chat, id)?.status, .failed)
        XCTAssertEqual(chat.retryAvailability(for: try XCTUnwrap(message(chat, id))), .now)
        chat.retry(messageId: id)
        try await waitUntil { message(chat, id)?.status == .sent }

        XCTAssertEqual(messagePosts, [id, id])
        XCTAssertEqual(message(chat, id)?.awaitsManualRetry, false)
    }

    func testClosingTheChatTurnsAShortWaitIntoAManualRetry() async throws {
        let (session, chat) = try prepare(Script(messages: [Self.limited("messages", seconds: 30)]))
        defer { finish(session, chat) }
        let id = await send(chat, "Closing")
        XCTAssertEqual(message(chat, id)?.awaitsManualRetry, false)

        chat.stopPolling()
        chat.startPolling()

        XCTAssertEqual(message(chat, id)?.awaitsManualRetry, true)
        XCTAssertEqual(session.store.chatCache.load().first { $0.id == id }?.awaitsManualRetry, true)
        XCTAssertNil(chat.automaticRetry)
        XCTAssertEqual(chat.retryAvailability(for: try XCTUnwrap(message(chat, id))), .waiting)
    }

    func testPhotoCooldownKeepsPhotosAndLetsTextThrough() async throws {
        let (session, chat) = try prepare(Script(uploads: [Self.limited("uploads", seconds: 600)]))
        defer { finish(session, chat) }
        let photo = await send(chat, "", photos: 1)
        let text = await send(chat, "Text still works")

        XCTAssertEqual(message(chat, photo)?.status, .failed)
        XCTAssertEqual(message(chat, photo)?.images.count, 1, "The photo stays with the held message")
        XCTAssertEqual(message(chat, photo)?.awaitsManualRetry, true)
        XCTAssertEqual(message(chat, text)?.status, .sent)
        XCTAssertTrue(chat.photosPaused)
        XCTAssertTrue(chat.cooldownAllowsSend(photos: false))
        XCTAssertFalse(chat.cooldownAllowsSend(photos: true))
        XCTAssertEqual(chat.composerCooldown?.scope, .uploads)
        XCTAssertEqual(messagePosts, [text])
    }

    func testRequestLimitDuringUploadHoldsTextToo() async throws {
        let (session, chat) = try prepare(Script(uploads: [Self.limited("requests", seconds: 45)]))
        defer { finish(session, chat) }
        let photo = await send(chat, "With photo", photos: 1)
        let text = await send(chat, "Text")

        XCTAssertEqual(chat.composerCooldown?.scope, .requests)
        XCTAssertFalse(chat.photosPaused)
        XCTAssertFalse(chat.cooldownAllowsSend(photos: false))
        XCTAssertEqual(message(chat, photo)?.status, .failed)
        XCTAssertEqual(message(chat, text)?.status, .failed)
        XCTAssertEqual(messagePosts, [], "A general limit holds every send")
        XCTAssertEqual(StubURLProtocol.requests.filter { $0.path == "/v1/uploads" }.count, 1)
    }

    func testKnownMessageCooldownSpendsNoUploadBudget() async throws {
        let (session, chat) = try prepare(Script(messages: [Self.limited("messages", seconds: 900)]))
        defer { finish(session, chat) }
        await send(chat, "Text first")
        let photo = await send(chat, "Photo second", photos: 2)

        XCTAssertEqual(message(chat, photo)?.status, .failed)
        XCTAssertEqual(message(chat, photo)?.images.count, 2)
        XCTAssertEqual(StubURLProtocol.requests.filter { $0.path == "/v1/uploads" }.count, 0)
        XCTAssertEqual(StubURLProtocol.requests.filter { $0.path == "/v1/devices/me" }.count, 1,
                       "The held send does not even update the device")
    }

    func testShortWaitDuringTheFirstLoadStaysAutomatic() async throws {
        let (session, chat) = try prepare(Script(messages: [Self.limited("messages", seconds: 1)]), polling: false)
        defer { finish(session, chat) }
        let id = await send(chat, "While loading")

        XCTAssertEqual(message(chat, id)?.awaitsManualRetry, false, "The chat is on screen, its first load is still running")
        guard case .automatic = chat.retryAvailability(for: try XCTUnwrap(message(chat, id))) else {
            return XCTFail("A short wait in a watched chat resends by itself")
        }
        try await waitUntil { message(chat, id)?.status == .sent }
        XCTAssertEqual(messagePosts, [id, id])
    }

    func testCancelKeepsLaterHeldMessagesBehindTheCanceledOne() async throws {
        let (session, chat) = try prepare(Script(messages: [Self.limited("messages", seconds: 1)]))
        defer { finish(session, chat) }
        let first = await send(chat, "First")
        let second = await send(chat, "Second")

        chat.cancelAutomaticRetry(messageId: first)
        try await Task.sleep(for: .milliseconds(1600))

        XCTAssertEqual(message(chat, first)?.awaitsManualRetry, true)
        XCTAssertEqual(message(chat, second)?.awaitsManualRetry, true, "The later message must not overtake the first")
        XCTAssertEqual(messagePosts, [first])
    }

    func testNewSendsWaitWhileHeldMessagesGoOutAgain() async throws {
        let gate = StubURLProtocol.Gate()
        let resend = StubURLProtocol.Reply(status: 201, body: Self.confirmation(seq: 2), gate: gate)
        let (session, chat) = try prepare(Script(messages: [Self.limited("messages", seconds: 1), resend]))
        defer { gate.release(); finish(session, chat) }
        let id = await send(chat, "Held")
        try await waitUntil { message(chat, id)?.status == .sending }

        XCTAssertNil(chat.composerCooldown, "The wait itself is over")
        XCTAssertFalse(chat.cooldownAllowsSend(photos: false), "A new message would overtake the resend")
        gate.release()
        try await waitUntil { chat.cooldownAllowsSend(photos: false) }
    }

    func testClosingWhileHeldMessagesDrainMakesTheRestManual() async throws {
        let gate = StubURLProtocol.Gate()
        let resend = StubURLProtocol.Reply(status: 201, body: Self.confirmation(seq: 2), gate: gate)
        let (session, chat) = try prepare(Script(messages: [Self.limited("messages", seconds: 1), resend]))
        defer { gate.release(); finish(session, chat) }
        let first = await send(chat, "First")
        let second = await send(chat, "Second")
        try await waitUntil { message(chat, first)?.status == .sending }
        XCTAssertNil(chat.cooldown(for: try XCTUnwrap(message(chat, second))), "The second message's wait is over too")

        chat.stopPolling()

        XCTAssertEqual(message(chat, second)?.awaitsManualRetry, true, "Nothing may go out later without the person")
    }

    func testLongerWaitArrivingWhileWaitingTurnsTheResendManual() async throws {
        let (session, chat) = try prepare(Script(messages: [Self.limited("messages", seconds: 1)]))
        defer { finish(session, chat) }
        let id = await send(chat, "Short first")
        session.cooldowns.impose(.messages, seconds: 3600)

        XCTAssertEqual(chat.retryAvailability(for: try XCTUnwrap(message(chat, id))), .waiting)
        try await waitUntil { message(chat, id)?.awaitsManualRetry == true }
        XCTAssertEqual(messagePosts, [id])
    }

    nonisolated private static func confirmation(seq: Int) -> String {
        #"{"conversation":{"id":"c1","status":"OPEN","unreadForUser":0,"createdAt":"2026-09-25T10:00:00.000Z"},"message":{"id":"m\#(seq)","clientId":null,"seq":\#(seq),"sender":"USER","kind":"TEXT","text":"x","attachments":[],"actionClickedAt":null,"createdAt":"2026-09-25T10:00:00.000Z"}}"#
    }
}
