import XCTest
@testable import Reception

/// The banner's one-second grace measures a link that is down, so it runs only while the chat listens: an opening
/// that takes longer (an automation's message is revealed after the team's typing dots) shows nothing.
@MainActor
final class ConnectionGraceTests: XCTestCase {
    /// A chat with a conversation whose live stream never comes up, after its network watch answered.
    private func opening() async throws -> LimitReleaseFixture {
        let f = try LimitReleaseFixture()
        f.session.store.hasConversation = true
        StubURLProtocol.install { [script = f.script] request in
            request.path == "/v1/conversation/events" ? .init(gate: StubURLProtocol.Gate()) : script.reply(request)
        }
        f.chat.startMonitoring()
        try await f.waitUntil { f.chat.pathSatisfied != nil }
        return f
    }

    func testTheOpeningShowsNoBannerAndAStreamThatDoesNotComeUpShowsAfterTheGrace() async throws {
        let f = try await opening()
        defer { f.finish() }
        try XCTSkipUnless(f.chat.pathSatisfied == true, "Needs a network path on the Mac")
        XCTAssertNil(f.chat.linkGrace, "Before the chat listens no link is down, however long the opening takes")
        XCTAssertEqual(f.chat.connection, .hidden)
        f.chat.startPolling()
        XCTAssertNotNil(f.chat.linkGrace, "The grace counts from listening")
        XCTAssertEqual(f.chat.connection, .hidden)
        try await f.waitUntil { f.chat.connection == .connecting }
    }

    func testNoNetworkShowsAtOnceDuringTheOpening() async throws {
        let f = try await opening()
        defer { f.finish() }
        f.chat.pathSatisfied = false
        f.chat.refreshConnection()
        XCTAssertEqual(f.chat.connection, .offline)
    }
}
