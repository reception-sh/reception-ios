import XCTest
import os
@testable import Reception

/// The live stream must come back on its own after a drop, and never give up for good while the chat stays open.
@MainActor
final class StreamReconnectTests: XCTestCase {
    private nonisolated static let messages = #"{"conversation":\#(LimitReleaseFixture.Script.conversation),"messages":[],"boundedRead":true}"#
    private nonisolated static let dropped = StubURLProtocol.Reply(body: "retry: 2000\n\n: ping\n\n", failAfterData: .networkConnectionLost)
    private nonisolated static let open = StubURLProtocol.Reply(body: "retry: 2000\n\n", holdOpen: true)

    private func fixture(events: @escaping @Sendable (Int) -> StubURLProtocol.Reply) throws -> LimitReleaseFixture {
        let f = try LimitReleaseFixture()
        Reception.shared.updatesAppBadge = false
        f.session.store.hasConversation = true
        let count = OSAllocatedUnfairLock(initialState: 0)
        StubURLProtocol.install { [script = f.script] request in
            switch (request.method, request.path) {
            case ("GET", "/v1/conversation/events"): return events(count.withLock { $0 += 1; return $0 })
            case ("GET", "/v1/conversation/messages"): return .init(body: Self.messages)
            case ("POST", "/v1/conversation/read"): return .init(body: #"{"conversationId":"c1","readSeq":0,"unreadCount":0}"#)
            default: return script.reply(request)
            }
        }
        return f
    }

    private func finish(_ f: LimitReleaseFixture) {
        f.finish()
        Reception.shared.updatesAppBadge = true
    }

    private func streamRequests() -> Int { StubURLProtocol.requests.filter { $0.path == "/v1/conversation/events" }.count }

    /// Transient failures that are due now, so the next attempt waits for nothing.
    private func failures(_ count: Int) -> RetryState {
        var state = RetryState()
        for _ in 0..<count { state.failed(ReceptionAPIError(code: "http_error", status: 503, retryAfter: 0)) }
        return state
    }

    func testStreamReconnectsAfterTheConnectionIsLost() async throws {
        let f = try fixture { $0 == 1 ? Self.dropped : Self.open }
        defer { finish(f) }
        f.chat.startPolling()
        try await f.waitUntil { self.streamRequests() == 2 && f.chat.streamConnected }
        XCTAssertEqual(f.session.retries["stream"]?.attempts, 1)
    }

    func testStreamReconnectsAfterTheServiceClosesIt() async throws {
        let f = try fixture { $0 == 1 ? .init(body: "retry: 2000\n\n: ping\n\n") : Self.open }
        defer { finish(f) }
        f.chat.startPolling()
        try await f.waitUntil { self.streamRequests() == 2 && f.chat.streamConnected }
    }

    func testAStreamThatStayedUpStartsAFreshBackoffWhenItDrops() async throws {
        let f = try fixture { $0 == 1 ? Self.dropped : Self.open }
        defer { finish(f) }
        f.session.retries["stream"] = failures(7)
        f.chat.healthyStreamDuration = .zero
        f.chat.startPolling()
        try await f.waitUntil { self.streamRequests() == 2 && f.chat.streamConnected }
        XCTAssertEqual(f.session.retries["stream"]?.attempts, 1, "The old failures are forgotten")
    }

    func testEightFailuresInARowOnlySlowTheRetriesDown() async throws {
        let f = try fixture { $0 == 1 ? Self.dropped : Self.open }
        defer { finish(f) }
        f.chat.exhaustedStreamRetryInterval = .milliseconds(50)
        f.chat.startPolling()
        // Seven earlier failures: the drop below is the eighth in a row.
        f.session.retries["stream"] = failures(7)
        try await f.waitUntil { self.streamRequests() == 2 && f.chat.streamConnected }
        XCTAssertNil(f.session.retries["stream"], "The slow retry starts over")
    }

    func testReopeningTheChatRetriesAStreamThatGaveUp() async throws {
        let f = try fixture { _ in Self.open }
        defer { finish(f) }
        f.session.retries["stream"] = failures(8)
        XCTAssertEqual(f.session.retries["stream"]?.stopped, true)
        f.chat.startPolling()
        try await f.waitUntil { self.streamRequests() == 1 && f.chat.streamConnected }
    }
}
