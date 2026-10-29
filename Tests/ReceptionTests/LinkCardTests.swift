import SwiftUI
import XCTest
@testable import Reception

@MainActor
final class LinkCardTests: XCTestCase {
    private var session: DeviceSession!
    private var chat: ChatModel!
    private var closes = 0
    private var events = 0
    private var previous: (DeviceSession?, (@MainActor (URL) -> Bool)?, ((ReceptionEvent) -> Void)?)

    override func setUp() async throws {
        let reception = Reception.shared
        previous = (reception.session, reception.onLink, reception.onEvent)
        let store = DeviceStore(scope: UUID().uuidString, credentialStorage: .init(read: { _ in .missing }, save: { _, _ in true }, delete: { _ in true }))
        session = DeviceSession(api: ReceptionAPI(appId: "app_abcdefghijklmnopqrstuv", baseURL: try XCTUnwrap(URL(string: "https://example.invalid"))), store: store)
        reception.session = session
        reception.onEvent = { [unowned self] in if case .linkOpened = $0 { events += 1 } }
        chat = ChatModel(session: session)
        chat.closePresentedChat = { [unowned self] next in closes += 1; next() }
    }

    override func tearDown() async throws {
        session.invalidate()
        Reception.shared.session = previous.0
        Reception.shared.onLink = previous.1
        Reception.shared.onEvent = previous.2
    }

    func testDecodingKeepsTheMessageWhenTheLinkIsUnusable() throws {
        XCTAssertEqual(try decode(#""linkUrl":"exampleapp://plans?tab=2""#).linkUrl?.absoluteString, "exampleapp://plans?tab=2")
        for field in [#""linkUrl":"""#, #""linkUrl":42"#, #""linkUrl":null"#, #""buttonLabel":"Open""#] {
            let message = try decode(field)
            XCTAssertNil(message.linkUrl, field)
            XCTAssertEqual(message.kind, "LINK")
            XCTAssertEqual(message.text, "Here you go")
        }
    }

    func testSchemeAllowlist() throws {
        for allowed in ["https://example.com", "HTTP://example.com", "mailto:help@example.com", "tel:+15551234", "sms:+15551234",
                        "exampleapp://plans", "Examples.App+x-1://open"] {
            XCTAssertTrue(LinkPolicy.isAllowed(try XCTUnwrap(URL(string: allowed))), allowed)
        }
        for blocked in ["javascript:alert(1)", "JavaScript:alert(1)", "data:text/html,hi", "file:///etc/hosts", "blob:https://example.com/1",
                        "about:blank", "vbscript:msgbox", "example.com/path"] {
            XCTAssertFalse(LinkPolicy.isAllowed(try XCTUnwrap(URL(string: blocked))), blocked)
        }
    }

    func testHostSchemesComeFromTheInfoDictionary() throws {
        let policy = LinkPolicy(infoDictionary: ["CFBundleURLTypes": [
            ["CFBundleURLSchemes": ["ExampleApp", "fb123"]], ["CFBundleURLName": "no schemes"], ["CFBundleURLSchemes": ["bad scheme", "exampleapp"]]
        ]])
        XCTAssertEqual(policy.hostSchemes, ["exampleapp", "fb123"])
        XCTAssertTrue(policy.isHostScheme(try XCTUnwrap(URL(string: "EXAMPLEAPP://plans"))))
        XCTAssertFalse(policy.isHostScheme(try XCTUnwrap(URL(string: "https://exampleapp.com"))))
        XCTAssertTrue(LinkPolicy(infoDictionary: nil).hostSchemes.isEmpty)
    }

    func testHandledLinkClosesTheChatFirst() throws {
        var handled: [URL] = []
        Reception.shared.onLink = { [unowned self] url in
            XCTAssertEqual(closes, 1, "the chat closes before the handler runs")
            handled.append(url)
            return true
        }
        chat.openExternal = { _, _ in XCTFail("a handled link is not opened by the system") }
        let url = try XCTUnwrap(URL(string: "exampleapp://plans"))
        chat.openLink(url, messageId: "link")
        XCTAssertEqual(handled, [url])
        XCTAssertEqual(events, 1)
        XCTAssertEqual(session.store.pendingActionClicks, ["link"])
        XCTAssertEqual(session.store.actionClickOutcomes, ["link": "handled"])
    }

    func testDeclinedLinkOpensThroughTheSystem() async throws {
        Reception.shared.onLink = { _ in false }
        let url = try XCTUnwrap(URL(string: "https://example.com/help"))
        var opened: [URL] = []
        var accepts = true
        chat.openExternal = { url, completion in opened.append(url); completion(accepts) }
        chat.openLink(url, messageId: "accepted")
        accepts = false
        chat.openLink(url, messageId: "refused")
        await waitUntil { self.session.store.actionClickOutcomes.count == 2 }
        XCTAssertEqual(opened, [url, url])
        XCTAssertEqual(closes, 2)
        XCTAssertEqual(events, 2)
        XCTAssertEqual(session.store.actionClickOutcomes, ["accepted": "opened", "refused": "failed"])
    }

    func testHostSchemeWithoutHandlerClosesThenOpens() async throws {
        let main = LinkPolicy.main
        LinkPolicy.main = LinkPolicy(infoDictionary: ["CFBundleURLTypes": [["CFBundleURLSchemes": ["exampleapp"]]]])
        defer { LinkPolicy.main = main }
        Reception.shared.onLink = nil
        var steps: [String] = []
        chat.closePresentedChat = { next in steps.append("close"); next() }
        chat.openExternal = { _, completion in steps.append("open"); completion(true) }
        chat.openLink(try XCTUnwrap(URL(string: "exampleapp://plans")), messageId: "deep")
        await waitUntil { self.session.store.actionClickOutcomes["deep"] != nil }
        XCTAssertEqual(steps, ["close", "open"])
        XCTAssertEqual(events, 1)
        XCTAssertEqual(session.store.actionClickOutcomes, ["deep": "opened"])
    }

    func testWebLinkWithoutHandlerKeepsTheChatOpen() async throws {
        Reception.shared.onLink = nil
        let url = try XCTUnwrap(URL(string: "https://apps.apple.com/redeem?ctx=offercodes&id=1&code=SAVE"))
        chat.openExternal = { _, completion in completion(true) }
        chat.openLink(url, messageId: "web")
        chat.openExternal = { _, completion in completion(false) }
        chat.openLink(url, messageId: "offline")
        await waitUntil { self.session.store.actionClickOutcomes.count == 2 }
        XCTAssertEqual(closes, 0)
        XCTAssertEqual(events, 2)
        XCTAssertEqual(session.store.pendingActionClicks, ["web", "offline"])
        XCTAssertEqual(session.store.actionClickOutcomes, ["web": "opened", "offline": "failed"])
    }

    func testTapsDuringTheCloseAreIgnored() throws {
        var handled = 0
        Reception.shared.onLink = { _ in handled += 1; return true }
        var finishClose: (() -> Void)?
        chat.closePresentedChat = { next in finishClose = next }
        let url = try XCTUnwrap(URL(string: "exampleapp://plans"))
        chat.openLink(url, messageId: "first")
        chat.openLink(url, messageId: "second")
        try XCTUnwrap(finishClose)()
        XCTAssertEqual(handled, 1)
        XCTAssertEqual(events, 1)
        XCTAssertEqual(session.store.pendingActionClicks, ["first"])
        XCTAssertEqual(session.store.actionClickOutcomes, ["first": "handled"])
    }

    func testLaterFailureKeepsAQueuedSuccess() {
        session.recordActionClick("link", outcome: .opened)
        session.recordActionClick("link", outcome: .failed)
        XCTAssertEqual(session.store.actionClickOutcomes, ["link": "opened"])
        session.recordActionClick("retry", outcome: .failed)
        session.recordActionClick("retry", outcome: .handled)
        XCTAssertEqual(session.store.actionClickOutcomes["retry"], "handled")
        XCTAssertEqual(session.store.pendingActionClicks, ["link", "retry"])
    }

    func testCacheKeepsTheLink() throws {
        let message = Message(id: "link", seq: 1, sender: "AGENT", text: "Your offer", attachments: [], createdAt: Date(),
                              kind: "LINK", linkUrl: URL(string: "exampleapp://plans"), buttonLabel: "See plans")
        session.store.chatCache.save([message])
        let cached = try XCTUnwrap(session.store.chatCache.load().first)
        XCTAssertEqual(cached.kind, "LINK")
        XCTAssertEqual(cached.linkUrl, message.linkUrl)
        XCTAssertEqual(cached.buttonLabel, "See plans")
    }

    private func decode(_ field: String) throws -> Message {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Message.self, from: Data("""
        {"id":"m", "seq":1, "sender":"AGENT", "text":"Here you go", "attachments":[], "createdAt":"2026-10-29T10:00:00Z", "kind":"LINK", \(field)}
        """.utf8))
    }

    private func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = Date().addingTimeInterval(2)
        while !condition() {
            guard Date() < deadline else { return XCTFail("condition not met within 2 seconds", file: file, line: line) }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }
}
