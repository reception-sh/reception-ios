import XCTest
import os
@testable import Reception

/// A chat open on its welcome screen, before anyone wrote, learns that its conversation exists: an automation's
/// message, a scheduled one arriving, a push for the team's first reply, the person's own first send. Each time the
/// open chat shows the conversation and listens on the live stream; a close meanwhile ends the load and the stream.
@MainActor
final class ConversationStartTests: XCTestCase {
    /// The service: one conversation once something started it, with the team's message `m1`.
    private final class Service: Sendable {
        struct State {
            var conversation = false
            var scheduled = false
            var incrementalReturnsMessage = false
            var conversationGate: StubURLProtocol.Gate?
            var unreadGate: StubURLProtocol.Gate?
            var sendGate: StubURLProtocol.Gate?
        }
        let state = OSAllocatedUnfairLock(initialState: State())
        private let conversation = LimitReleaseFixture.Script.conversation
        private let teamMessage = #"{"id":"m1","seq":1,"sender":"AGENT","text":"Hi","attachments":[],"createdAt":"2026-09-25T10:00:00.000Z"}"#

        func reply(_ request: StubURLProtocol.Request, script: LimitReleaseFixture.Script) -> StubURLProtocol.Reply {
            let current = state.withLock { $0 }
            switch (request.method, request.path) {
            case ("GET", "/v1/automations"): return .init(body: #"{"events":["welcome_event"]}"#)
            case ("POST", "/v1/automations/events"):
                if current.scheduled { return .init(body: #"{"sent":false,"scheduled":true,"openChat":false}"#) }
                state.withLock { $0.conversation = true }
                return .init(body: #"{"sent":true,"openChat":false}"#)
            case ("GET", "/v1/conversation/unread"):
                return .init(body: #"{"hasConversation":\#(current.conversation),"unreadCount":0}"#, gate: current.unreadGate)
            case ("GET", "/v1/conversation"):
                return .init(body: current.conversation
                    ? #"{"conversation":\#(conversation),"messages":[\#(teamMessage)],"boundedRead":true}"#
                    : #"{"conversation":null,"messages":[]}"#, gate: current.conversationGate)
            case ("GET", "/v1/conversation/events"): return .init(body: "retry: 2000\n\n", holdOpen: true)
            case ("GET", "/v1/conversation/messages"):
                if current.incrementalReturnsMessage, request.query == "after=0" {
                    return .init(body: #"{"conversation":\#(conversation),"messages":[\#(teamMessage)],"boundedRead":true}"#)
                }
                return .init(body: #"{"conversation":\#(conversation),"messages":[],"boundedRead":true}"#)
            case ("POST", "/v1/conversation/read"): return .init(body: #"{"conversationId":"c1","readSeq":9,"unreadCount":0}"#)
            case ("POST", "/v1/conversation/messages"):
                if let gate = current.sendGate { return .init(status: 500, gate: gate) }
                state.withLock { $0.conversation = true }
                return script.reply(request)
            default: return script.reply(request)
            }
        }
    }
    private let service = Service()

    /// A chat that nobody wrote in, opened the way `ChatContent` opens it.
    private func openOnWelcomeScreen() async throws -> LimitReleaseFixture {
        // The listened events are cached per App ID, so each test gets its own.
        let f = try LimitReleaseFixture(appId: "app_" + UUID().uuidString.filter(\.isLetter).prefix(22)
            .padding(toLength: 22, withPad: "x", startingAt: 0))
        Reception.shared.updatesAppBadge = false
        Reception.shared.cancelUnreadRefresh()
        f.session.store.hasStartedChat = false
        Reception.shared.usePreviewChat(f.chat)
        StubURLProtocol.install { [script = f.script, service] in service.reply($0, script: script) }
        f.chat.startMonitoring()
        await f.chat.load(recheckLimits: true)
        f.chat.startPolling()
        XCTAssertTrue(f.chat.messages.isEmpty)
        return f
    }

    private func finish(_ f: LimitReleaseFixture) {
        service.state.withLock { state in
            state.conversationGate?.release()
            state.unreadGate?.release()
            state.sendGate?.release()
        }
        f.finish()
        Reception.shared.updatesAppBadge = true
    }

    private func requests(_ method: String, _ path: String) -> Int {
        StubURLProtocol.requests.filter { $0.method == method && $0.path == path }.count
    }

    /// `send(text:images:)` without its notification settings read, which the test host cannot answer.
    private func sendFirstMessage(_ f: LimitReleaseFixture) {
        let message = Message(id: UUID().uuidString, sender: "USER", text: "Hello", attachments: [],
                              createdAt: Date(), status: .sending)
        f.chat.messages.append(message)
        f.session.store.hasStartedChat = true
        f.chat.submit(message.id, userInitiated: true)
        f.chat.startPolling()
    }

    private func assertShowsTheConversationAndListens(_ f: LimitReleaseFixture) async throws {
        try await f.waitUntil { f.chat.messages.map(\.id).contains("m1") }
        try await f.waitUntil { f.chat.streamConnected }
        XCTAssertEqual(requests("GET", "/v1/conversation/events"), 1)
    }

    func testAnAutomationsMessageAppearsInTheOpenChatAndTheChatListens() async throws {
        let f = try await openOnWelcomeScreen()
        defer { finish(f) }
        Reception.shared.automations.track("welcome_event", opensChat: false, session: f.session)
        try await assertShowsTheConversationAndListens(f)
    }

    func testAnAutomationsMessageAppearsWhileAnOlderUnreadRefreshIsOnItsWay() async throws {
        let gate = StubURLProtocol.Gate()
        let f = try await openOnWelcomeScreen()
        defer { finish(f) }
        service.state.withLock { $0.unreadGate = gate }
        // Asked before the automation wrote, so it answers that there is no conversation, and no second refresh starts
        // while it runs.
        Reception.shared.refreshUnread()
        try await f.waitUntil { self.requests("GET", "/v1/conversation/unread") == 1 }
        Reception.shared.automations.track("welcome_event", opensChat: false, session: f.session)
        try await assertShowsTheConversationAndListens(f)
        XCTAssertEqual(requests("GET", "/v1/conversation/unread"), 1)
        gate.release()
        try await f.waitUntil { !Reception.shared.isRefreshingUnread }
        XCTAssertTrue(f.session.store.hasConversation, "The older answer does not take the conversation back")
    }

    func testAScheduledAutomationsMessageAppearsWhenItArrivesAndTheChatListens() async throws {
        service.state.withLock { $0.scheduled = true }
        let f = try await openOnWelcomeScreen()
        defer { finish(f) }
        Reception.shared.automations.track("welcome_event", opensChat: false, session: f.session)
        try await f.waitUntil { f.session.store.hasStartedChat }
        // The message's time came: the unread refresh is the first to say that the conversation exists.
        service.state.withLock { $0.conversation = true }
        await f.chat.refreshUnread()
        try await assertShowsTheConversationAndListens(f)
    }

    func testAPushForTheTeamsFirstReplyLoadsItAndTheChatListens() async throws {
        let f = try await openOnWelcomeScreen()
        defer { finish(f) }
        service.state.withLock { $0.conversation = true }
        XCTAssertTrue(Reception.shared.handlePushNotification(userInfo: ["reception": ["conversationId": "c1"]], openChat: false))
        try await assertShowsTheConversationAndListens(f)
    }

    func testThePersonsFirstMessageStartsTheStream() async throws {
        let f = try await openOnWelcomeScreen()
        defer { finish(f) }
        sendFirstMessage(f)
        try await f.waitUntil { f.chat.streamConnected }
    }

    func testAnUnreadAnswerFromBeforeTheFirstSendKeepsTheConversation() async throws {
        let gate = StubURLProtocol.Gate()
        let f = try await openOnWelcomeScreen()
        defer { finish(f) }
        service.state.withLock { $0.unreadGate = gate }
        // Asked while nobody had written, so the service answers that there is no conversation.
        let refresh = Task { await f.chat.refreshUnread() }
        try await f.waitUntil { self.requests("GET", "/v1/conversation/unread") == 1 }
        sendFirstMessage(f)
        try await f.waitUntil { f.chat.streamConnected }
        gate.release()
        await refresh.value
        XCTAssertTrue(f.session.store.hasConversation, "The send that followed the question is newer than its answer")
    }

    func testACloseWhileTheConversationLoadsEndsTheLoadAndStartsNoStream() async throws {
        let gate = StubURLProtocol.Gate()
        let f = try await openOnWelcomeScreen()
        defer { finish(f) }
        service.state.withLock { state in
            state.conversation = true
            state.conversationGate = gate
        }
        XCTAssertTrue(Reception.shared.handlePushNotification(userInfo: ["reception": ["conversationId": "c1"]], openChat: false))
        try await f.waitUntil { self.requests("GET", "/v1/conversation") == 1 }
        f.chat.stopPolling()
        f.chat.isVisible = false
        gate.release()
        // Nothing is expected to happen; give a load or stream that wrongly continued the time to show.
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertTrue(f.chat.messages.isEmpty, "The closed chat shows nothing it loaded")
        XCTAssertEqual(requests("GET", "/v1/conversation/events"), 0)
        XCTAssertNil(f.chat.polling)
    }
    func testAnAutomationsMessageAppearsAfterAScheduledOneStartedTheChat() async throws {
        let gate = StubURLProtocol.Gate()
        let f = try await openOnWelcomeScreen()
        defer { finish(f) }
        // A prior scheduled automation already marked the chat started, but has not delivered.
        service.state.withLock { $0.scheduled = true }
        Reception.shared.automations.track("welcome_event", opensChat: false, session: f.session)
        try await f.waitUntil { f.session.store.hasStartedChat }
        service.state.withLock { $0.scheduled = false; $0.unreadGate = gate }
        Reception.shared.refreshUnread()
        try await f.waitUntil { self.requests("GET", "/v1/conversation/unread") == 1 }
        Reception.shared.automations.track("welcome_event", opensChat: false, session: f.session)
        try await assertShowsTheConversationAndListens(f)
        // The older answer, asked before the message, says there is no conversation.
        gate.release()
        try await f.waitUntil { !Reception.shared.isRefreshingUnread }
        XCTAssertTrue(f.session.store.hasConversation, "The older answer does not take the conversation back")
        XCTAssertEqual(requests("GET", "/v1/conversation/unread"), 1)
    }

    func testAnOlderEmptyLoadKeepsAConversationAPushNamedMeanwhile() async throws {
        let gate = StubURLProtocol.Gate()
        let f = try await openOnWelcomeScreen()
        defer { finish(f) }
        // Reopen after a scheduled automation: the opening GET still sees no conversation.
        f.chat.stopPolling()
        f.session.store.hasStartedChat = true
        service.state.withLock {
            $0.conversationGate = gate
            $0.sendGate = StubURLProtocol.Gate()
            $0.unreadGate = StubURLProtocol.Gate()
        }
        let oldLoad = Task { await f.chat.load() }
        try await f.waitUntil { self.requests("GET", "/v1/conversation") == 1 }
        // Sending while the opening is held activates polling, but no POST acknowledgment has arrived.
        sendFirstMessage(f)
        try await f.waitUntil { self.requests("POST", "/v1/conversation/messages") == 1 }
        service.state.withLock { $0.conversation = true; $0.incrementalReturnsMessage = true }
        Reception.shared.handlePushNotification(userInfo: ["reception": ["conversationId": "c1"]], openChat: false)
        try await f.waitUntil { f.chat.streamConnected }
        // The new conversationStarted() skipped its load because the old GET still holds loading.
        gate.release()
        await oldLoad.value
        XCTAssertTrue(f.session.store.hasConversation, "The pre-push empty response must not revoke the conversation")
        try await f.waitUntil { f.chat.messages.contains { $0.id == "m1" } }
        // The opening poll recovers the stored message, but a subsequent network return cannot restart the stream.
        f.chat.cancelStream()
        f.chat.startStream()
        XCTAssertNotNil(f.chat.polling, "The network-return path must still be able to start a stream")
    }

    func testAResetDuringTheTypingDotsLeavesTheNewChatsCursorAlone() async throws {
        let f = try await openOnWelcomeScreen()
        defer { finish(f) }
        Reception.shared.automations.track("welcome_event", opensChat: false, session: f.session)
        try await f.waitUntil { f.chat.isTyping && f.chat.loading }
        let owner = try XCTUnwrap(f.chat.conversationStart)
        XCTAssertFalse(f.chat.messages.contains { $0.id == "m1" })
        XCTAssertTrue(f.chat.handleReset(ReceptionAPIError(code: "chat_reset", status: 409, resetRevision: 2)))
        XCTAssertEqual(Reception.shared.session?.store.cursor, 0)
        await owner.value
        XCTAssertEqual(Reception.shared.session?.store.cursor, 0, "Cancelled reveal restored pre-reset cursor in the renewed store")
        XCTAssertFalse(f.chat.messages.contains { $0.id == "m1" })
        XCTAssertEqual(requests("POST", "/v1/conversation/read"), 0)
    }

    func testABackgroundDuringTheTypingDotsDoesNotCountTheMessageAsShown() async throws {
        let f = try await openOnWelcomeScreen()
        defer { finish(f) }
        Reception.shared.automations.track("welcome_event", opensChat: false, session: f.session)
        try await f.waitUntil { f.chat.isTyping && f.chat.loading }
        let owner = try XCTUnwrap(f.chat.conversationStart)
        // The model's background action from ChatContent; no simulated UIApplication state override.
        Reception.shared.applicationActive = false
        f.chat.stopPolling()
        await owner.value
        XCTAssertFalse(f.chat.messages.contains { $0.id == "m1" })
        XCTAssertEqual(f.chat.maxSeq, 0, "Cancelled reveal advanced past the unmerged message")
        XCTAssertNil(f.chat.polling)
        XCTAssertFalse(f.chat.loading)
        XCTAssertEqual(requests("POST", "/v1/conversation/read"), 0)
    }

    func testAReopenDuringTheTypingDotsShowsTheMessage() async throws {
        let f = try await openOnWelcomeScreen()
        defer { finish(f) }
        service.state.withLock { $0.incrementalReturnsMessage = true }
        Reception.shared.automations.track("welcome_event", opensChat: false, session: f.session)
        try await f.waitUntil { f.chat.isTyping && f.chat.loading }
        let owner = try XCTUnwrap(f.chat.conversationStart)
        f.chat.stopPolling()
        await f.chat.load(recheckLimits: true)
        f.chat.startPolling()
        await owner.value
        // The reopening load waited for the cancelled one to end and brings the message itself.
        try await f.waitUntil { f.chat.messages.contains { $0.id == "m1" } && !f.chat.loading }
        XCTAssertEqual(requests("GET", "/v1/conversation"), 2)
        XCTAssertEqual(f.chat.maxSeq, 1)
    }

    func testAnAutomationsMessageAppearsWhileAnOlderLoadAndUnreadRefreshAreOnTheirWay() async throws {
        let f = try await openOnWelcomeScreen()
        let loadGate = StubURLProtocol.Gate(), unreadGate = StubURLProtocol.Gate()
        let previousLevel = Reception.logLevel
        let previousHandler = Reception.logHandler
        let received = OSAllocatedUnfairLock(initialState: false)
        Reception.logLevel = .debug
        Reception.logHandler = { _, message in
            if message.contains("Automation message received for") { received.withLock { $0 = true } }
        }
        defer {
            loadGate.release(); unreadGate.release(); finish(f)
            Reception.logLevel = previousLevel; Reception.logHandler = previousHandler
        }
        // A real scheduled response marks the chat started. On reopening, its empty GET is held.
        service.state.withLock { $0.scheduled = true }
        Reception.shared.automations.track("welcome_event", opensChat: false, session: f.session)
        try await f.waitUntil { f.session.store.hasStartedChat }
        f.chat.stopPolling()
        service.state.withLock {
            $0.scheduled = false; $0.conversationGate = loadGate; $0.unreadGate = unreadGate
            $0.incrementalReturnsMessage = true; $0.sendGate = StubURLProtocol.Gate()
        }
        Reception.shared.refreshUnread()
        let old = Task { await f.chat.load() }
        try await f.waitUntil { self.requests("GET", "/v1/conversation") == 1 && self.requests("GET", "/v1/conversation/unread") == 1 }
        // Sending during the opening activates the chat, while the POST acknowledgment is still withheld.
        sendFirstMessage(f)
        try await f.waitUntil { self.requests("POST", "/v1/conversation/messages") == 1 }
        Reception.shared.automations.track("welcome_event", opensChat: false, session: f.session)
        try await f.waitUntil { received.withLock { $0 } }
        // Wait for the attempted direct startup to finish skipping the already-busy load.
        await f.chat.conversationStart?.value
        loadGate.release(); await old.value
        try await f.waitUntil { f.chat.messages.contains { $0.id == "m1" } }
        XCTAssertTrue(f.session.store.hasConversation, "Sent automation never established conversation knowledge")
        XCTAssertNotNil(f.chat.polling, "No stream can recover the automation message")
        XCTAssertEqual(requests("GET", "/v1/conversation/unread"), 1)
    }
}
