import XCTest
@testable import Reception

@MainActor
final class ScreenLinkTests: XCTestCase {
    private var session: DeviceSession!
    private var chat: ChatModel!
    private var steps: [String] = []
    private var previous: (DeviceSession?, [ReceptionScreen]) = (nil, [])

    override func setUp() async throws {
        let reception = Reception.shared
        previous = (reception.session, reception.screens)
        let store = DeviceStore(scope: UUID().uuidString, credentialStorage: .init(read: { _ in .missing }, save: { _, _ in true }, delete: { _ in true }))
        session = DeviceSession(api: ReceptionAPI(appId: "app_abcdefghijklmnopqrstuv", baseURL: try XCTUnwrap(URL(string: "https://example.invalid"))), store: store)
        reception.session = session
        chat = ChatModel(session: session)
        chat.closePresentedChat = { [unowned self] next in steps.append("close"); next() }
        chat.presentWebLink = { [unowned self] _ in steps.append("safari"); return true }
        chat.openExternal = { [unowned self] _, completion in steps.append("system"); completion(true) }
        chat.openInClaimingApp = { _, completion in completion(false) }
    }

    override func tearDown() async throws {
        session.invalidate()
        Reception.shared.session = previous.0
        Reception.shared.screens = previous.1
    }

    func testScreenLinksParseTheirIdAndValue() throws {
        let order = try XCTUnwrap(ScreenLink(try XCTUnwrap(URL(string: "reception-screen:order?value=A%2012"))))
        XCTAssertEqual(order, ScreenLink(try XCTUnwrap(URL(string: "RECEPTION-SCREEN:order?value=A%2012"))))
        XCTAssertEqual([order.id, order.value], ["order", "A 12"])
        XCTAssertNil(try XCTUnwrap(ScreenLink(try XCTUnwrap(URL(string: "reception-screen:settings?value="))))?.value)
        for other in ["reception-screen:", "reception-screen:-x", "reception-screen:a/b", "myapp://settings", "https://example.com/settings"] {
            XCTAssertNil(ScreenLink(try XCTUnwrap(URL(string: other))), other)
        }
    }

    func testAScreenLinkClosesTheChatThenOpensTheScreen() throws {
        Reception.shared.screens = [
            ReceptionScreen("settings") { [unowned self] in steps.append("settings") },
            ReceptionScreen("order", value: "Order number") { [unowned self] number in steps.append("order \(number)") },
        ]
        chat.openLink(try XCTUnwrap(URL(string: "reception-screen:settings")), messageId: "a")
        chat.openLink(try XCTUnwrap(URL(string: "reception-screen:order?value=123")), messageId: "b")
        XCTAssertEqual(steps, ["close", "settings", "close", "order 123"])
        XCTAssertEqual(session.store.actionClickOutcomes, ["a": "handled", "b": "handled"])
        XCTAssertTrue(chat.isHostLink(try XCTUnwrap(URL(string: "reception-screen:settings"))))
    }

    func testAMissingScreenOrValueFails() throws {
        Reception.shared.screens = [ReceptionScreen("order", value: "Order number") { [unowned self] _ in steps.append("order") }]
        chat.openLink(try XCTUnwrap(URL(string: "reception-screen:order")), messageId: "no value")
        chat.openLink(try XCTUnwrap(URL(string: "reception-screen:gone")), messageId: "gone")
        XCTAssertEqual(steps, ["close", "close"])
        XCTAssertEqual(session.store.actionClickOutcomes, ["no value": "failed", "gone": "failed"])
    }

    func testScreensAreReportedOnceEachAndSynchronized() throws {
        let reception = Reception.shared
        reception.screens = [
            ReceptionScreen("settings") {}, ReceptionScreen("order", value: "Order number") { _ in },
            ReceptionScreen("settings") {}, ReceptionScreen("bad id") {}, ReceptionScreen(String(repeating: "a", count: 65)) {},
        ] + (0..<60).map { index in ReceptionScreen("screen\(index)") {} }
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: DeviceInfo.payload(identity: DeviceIdentity())) as? [String: Any])
        let reported = try XCTUnwrap(body["screens"] as? [[String: String]])
        XCTAssertEqual(reported.count, ScreenLink.limit)
        XCTAssertEqual(Array(reported.prefix(3)), [["id": "settings"], ["id": "order", "value": "Order number"], ["id": "screen0"]])
        XCTAssertNil(body["urlSchemes"], "links need no URL scheme report")
        XCTAssertNil(body["handlesLinks"])

        session.synchronizedPaywalls = reception.availablePaywalls
        session.synchronizedLanguage = ReceptionLocalization.appLanguage
        session.synchronizedAppBadge = reception.updatesAppBadge
        session.synchronizedSubscribed = reception.paidAccess.current
        session.synchronizedTransactionIds = reception.paidAccess.transactionIds
        session.synchronizedScreens = reported
        XCTAssertFalse(session.preferencesNeedSync)
        reception.screens = [ReceptionScreen("settings") {}]
        XCTAssertTrue(session.preferencesNeedSync, "a changed list is sent again")
    }
}
