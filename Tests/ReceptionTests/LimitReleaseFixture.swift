import XCTest
import os
@testable import Reception

@MainActor
final class LimitReleaseFixture {
    final class Script: Sendable {
        struct State {
            var conversation = StubURLProtocol.Reply(body: #"{"conversation":null,"messages":[],"limits":{"messages":0,"uploads":0}}"#)
            var sends: [StubURLProtocol.Reply] = []
            var seq = 0
        }
        let state = OSAllocatedUnfairLock(initialState: State())

        func reply(_ request: StubURLProtocol.Request) -> StubURLProtocol.Reply {
            switch request.path {
            case "/v1/devices/me": return .init(body: #"{"verifiedUserId":null}"#)
            case "/v1/conversation": return state.withLock { $0.conversation }
            case "/v1/conversation/events": return .init(status: 404, body: #"{"error":{"code":"no_conversation","message":"None"}}"#)
            case "/v1/conversation/messages":
                return state.withLock { state in
                    if !state.sends.isEmpty { return state.sends.removeFirst() }
                    state.seq += 1
                    let id = request.body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["clientId"] as? String ?? ""
                    return .init(status: 201, body: "{\"conversation\":\(Self.conversation),\"message\":\(Self.message(id, seq: state.seq))}")
                }
            default: return .init()
            }
        }

        static let conversation = #"{"id":"c1","status":"OPEN","unreadForUser":0,"createdAt":"2026-09-25T10:00:00.000Z"}"#
        static func message(_ id: String, seq: Int) -> String {
            #"{"id":"server-\#(seq)","clientId":"\#(id)","seq":\#(seq),"sender":"USER","text":"x","attachments":[],"createdAt":"2026-09-25T10:00:00.000Z"}"#
        }
        static func limited(_ scope: String, seconds: Int = 3600) -> StubURLProtocol.Reply {
            .init(status: 429, body: #"{"error":{"code":"rate_limited","message":"Wait","retryScope":"\#(scope)"}}"#,
                  headers: ["Retry-After": String(seconds)])
        }
    }

    let time = TestTime()
    let script = Script()
    let session: DeviceSession
    let chat: ChatModel

    init() throws {
        let reception = Reception.shared
        reception.usesRemoteAppearance = false
        reception.applicationActive = true
        reception.unreadMonitor.setActive(false)
        reception.session?.deactivate()
        let store = DeviceStore(scope: "release-" + UUID().uuidString, credentialStorage: .init(
            read: { _ in .missing }, save: { _, _ in true }, delete: { _ in true }))
        store.hasStartedChat = true
        let api = ReceptionAPI(appId: "app_abcdefghijklmnopqrstuv", baseURL: try XCTUnwrap(URL(string: "https://reception.test")))
        session = DeviceSession(api: api, store: store, now: { [time] in time.now })
        session.credentials = SessionCredentials(sessionSecret: "secret", verifiedUserId: nil)
        session.accessToken = "access"
        reception.session = session
        chat = ChatModel(session: session)
        chat.isVisible = true
        session.cooldowns.onChange = { [weak chat] in chat?.cooldownsChanged() }
        StubURLProtocol.install { [script] in script.reply($0) }
    }

    func finish() {
        chat.stopPolling()
        session.invalidate()
        Reception.shared.session = nil
        Reception.shared.applicationActive = false
        Reception.shared.usesRemoteAppearance = true
        StubURLProtocol.uninstall()
    }

    @discardableResult
    func held(_ id: String, photos: Bool = false, eligible: Bool = true) -> String {
        var message = Message(id: id, sender: "USER", text: id, attachments: [],
                              createdAt: Date().addingTimeInterval(Double(chat.messages.count)), status: .failed,
                              awaitsManualRetry: true, retryAfterLimitRelease: eligible)
        if photos {
            message.images = [UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { _ in }]
            message.attachmentIds = ["uploaded-photo"]
        }
        chat.messages.append(message)
        chat.saveMessages()
        return id
    }

    var posts: [String] {
        StubURLProtocol.requests.filter { $0.path == "/v1/conversation/messages" }.compactMap {
            $0.body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["clientId"] as? String
        }
    }

    func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(4)
        while !condition() {
            guard Date() < deadline else { XCTFail("Condition not reached"); return }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}
