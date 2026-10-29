import SwiftUI
import XCTest
@testable import Reception

@MainActor
final class WebLinkTests: XCTestCase {
    private var session: DeviceSession!
    private var chat: ChatModel!
    private var steps: [String] = []
    private var previous: (DeviceSession?, (@MainActor (URL) -> Bool)?, Bool) = (nil, nil, true)

    override func setUp() async throws {
        let reception = Reception.shared
        previous = (reception.session, reception.onLink, reception.opensWebLinksInApp)
        let store = DeviceStore(scope: UUID().uuidString, credentialStorage: .init(read: { _ in .missing }, save: { _, _ in true }, delete: { _ in true }))
        session = DeviceSession(api: ReceptionAPI(appId: "app_abcdefghijklmnopqrstuv", baseURL: try XCTUnwrap(URL(string: "https://example.invalid"))), store: store)
        reception.session = session
        reception.onLink = nil
        reception.opensWebLinksInApp = true
        chat = ChatModel(session: session)
        chat.closePresentedChat = { [unowned self] next in steps.append("close"); next() }
        chat.presentWebLink = { [unowned self] _ in steps.append("safari"); return true }
        chat.openExternal = { [unowned self] _, completion in steps.append("system"); completion(true) }
    }

    override func tearDown() async throws {
        session.invalidate()
        Reception.shared.session = previous.0
        Reception.shared.onLink = previous.1
        Reception.shared.opensWebLinksInApp = previous.2
    }

    func testWebLinkClassification() throws {
        for web in ["https://example.com/help", "http://example.com", "HTTPS://Example.com/a?b=c"] {
            XCTAssertTrue(LinkPolicy.isWebLink(try XCTUnwrap(URL(string: web))), web)
        }
        for other in ["https://apps.apple.com/redeem?ctx=offercodes&id=1&code=SAVE", "https://itunes.apple.com/app/id1",
                      "https://APPS.apple.com/app/id1", "https://de.apps.apple.com/app/id1", "mailto:help@example.com",
                      "exampleapp://plans", "https:///path"] {
            XCTAssertFalse(LinkPolicy.isWebLink(try XCTUnwrap(URL(string: other))), other)
        }
    }

    func testWebLinkOpensInSafariOverTheChat() throws {
        var presented: [URL] = []
        chat.presentWebLink = { presented.append($0); return true }
        let url = try XCTUnwrap(URL(string: "https://example.com/help"))
        chat.openLink(url, messageId: "web")
        XCTAssertEqual(presented, [url])
        XCTAssertEqual(steps, [], "the system is not asked and the chat stays open")
        XCTAssertEqual(session.store.actionClickOutcomes, ["web": "opened"])
    }

    func testWebLinkGoesToTheSystemWhenTheSettingIsOff() async throws {
        Reception.shared.opensWebLinksInApp = false
        chat.openLink(try XCTUnwrap(URL(string: "https://example.com/help")), messageId: "web")
        await waitUntil { self.session.store.actionClickOutcomes["web"] != nil }
        XCTAssertEqual(steps, ["system"])
        XCTAssertEqual(session.store.actionClickOutcomes, ["web": "opened"])
    }

    func testMissingPresenterFallsBackToTheSystem() async throws {
        chat.presentWebLink = { [unowned self] _ in steps.append("no screen"); return false }
        chat.openLink(try XCTUnwrap(URL(string: "https://example.com/help")), messageId: "web")
        await waitUntil { self.session.store.actionClickOutcomes["web"] != nil }
        XCTAssertEqual(steps, ["no screen", "system"])
        XCTAssertEqual(session.store.actionClickOutcomes, ["web": "opened"])
    }

    func testDeclinedWebLinkOpensInSafariAfterTheChatClosed() throws {
        Reception.shared.onLink = { [unowned self] _ in steps.append("handler"); return false }
        chat.openLink(try XCTUnwrap(URL(string: "https://example.com/help")), messageId: "web")
        XCTAssertEqual(steps, ["close", "handler", "safari"])
        XCTAssertEqual(session.store.actionClickOutcomes, ["web": "opened"])
    }

    func testAppStoreLinkStaysWithTheSystem() async throws {
        chat.openLink(try XCTUnwrap(URL(string: "https://apps.apple.com/redeem?ctx=offercodes&id=1&code=SAVE")), messageId: "store")
        await waitUntil { self.session.store.actionClickOutcomes["store"] != nil }
        XCTAssertEqual(steps, ["system"])
    }

    func testTextLinksOpenWebPagesInSafari() throws {
        assertResult(chat.openTextLink(try XCTUnwrap(URL(string: "https://example.com"))), .handled)
        XCTAssertEqual(steps, ["safari"])
        assertResult(chat.openTextLink(try XCTUnwrap(URL(string: "https://apps.apple.com/app/id1"))), .systemAction)
        Reception.shared.opensWebLinksInApp = false
        assertResult(chat.openTextLink(try XCTUnwrap(URL(string: "https://example.com"))), .systemAction)
        chat.presentWebLink = { _ in false }
        Reception.shared.opensWebLinksInApp = true
        assertResult(chat.openTextLink(try XCTUnwrap(URL(string: "https://example.com"))), .systemAction)
        XCTAssertEqual(steps, ["safari"], "text links never reach openExternal")
        XCTAssertTrue(session.store.actionClickOutcomes.isEmpty)
    }

    /// `OpenURLAction.Result` is not `Equatable`; its description tells the cases apart.
    private func assertResult(_ result: OpenURLAction.Result, _ expected: OpenURLAction.Result, line: UInt = #line) {
        XCTAssertEqual(String(describing: result), String(describing: expected), line: line)
        XCTAssertNotEqual(String(describing: OpenURLAction.Result.handled), String(describing: OpenURLAction.Result.systemAction))
    }

    private func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = Date().addingTimeInterval(2)
        while !condition() {
            guard Date() < deadline else { return XCTFail("condition not met within 2 seconds", file: file, line: line) }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }
}
