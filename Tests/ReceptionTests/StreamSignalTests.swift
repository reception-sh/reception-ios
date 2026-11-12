import XCTest
@testable import Reception

/// A "changed" signal from the live stream must never be lost, also when it arrives while another GET is running.
@MainActor
final class StreamSignalTests: XCTestCase {
    private nonisolated static let conversation = LimitReleaseFixture.Script.conversation
    private nonisolated static func message(_ id: String, seq: Int) -> String {
        #"{"id":"\#(id)","seq":\#(seq),"sender":"AGENT","text":"Hi","attachments":[],"createdAt":"2026-09-25T10:00:00.000Z"}"#
    }

    func testASignalDuringTheLoadPollsOnceTheLoadEnds() async throws {
        let f = try LimitReleaseFixture()
        Reception.shared.updatesAppBadge = false
        let load = StubURLProtocol.Gate()
        defer {
            load.release()
            f.finish()
            Reception.shared.updatesAppBadge = true
        }
        f.session.store.hasConversation = true
        StubURLProtocol.install { [script = f.script] request in
            switch (request.method, request.path) {
            // Answered before the team's reply, which the signal below announces.
            case ("GET", "/v1/conversation"):
                return .init(body: #"{"conversation":\#(Self.conversation),"messages":[\#(Self.message("m1", seq: 1))],"boundedRead":true}"#, gate: load)
            case ("GET", "/v1/conversation/messages"):
                return .init(body: #"{"conversation":\#(Self.conversation),"messages":[\#(Self.message("m2", seq: 2))],"boundedRead":true}"#)
            // The stream stays quiet; the test delivers its signal with poll().
            case ("GET", "/v1/conversation/events"): return .init(gate: StubURLProtocol.Gate())
            case ("POST", "/v1/conversation/read"): return .init(body: #"{"conversationId":"c1","readSeq":9,"unreadCount":0}"#)
            default: return script.reply(request)
            }
        }
        f.chat.startPolling()
        let loading = Task { await f.chat.load() }
        try await f.waitUntil { StubURLProtocol.requests.contains { $0.method == "GET" && $0.path == "/v1/conversation" } }
        // The stream's "changed" arrives while the load's GET is on its way.
        await f.chat.poll()
        load.release()
        await loading.value
        try await f.waitUntil { f.chat.messages.map(\.id) == ["m1", "m2"] }
    }
}
