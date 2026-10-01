import XCTest
@testable import Reception

final class PaywallTests: XCTestCase {
    @MainActor
    func testDevicePayloadAndValidation() throws {
        let previous = Reception.shared.paywalls
        defer { Reception.shared.paywalls = previous }
        Reception.shared.paywalls = [
            ReceptionPaywall(id: " support_chat\n", title: " Support offer "),
            ReceptionPaywall(id: "support_chat", title: "Duplicate"),
            ReceptionPaywall(id: "bad id", title: "Invalid"),
            ReceptionPaywall(id: "", title: "Empty"),
            ReceptionPaywall(id: String(repeating: "x", count: 65), title: "Long ID"),
            ReceptionPaywall(id: "long", title: String(repeating: "x", count: 61)),
            ReceptionPaywall(id: "blank", title: " \n")
        ]
        XCTAssertEqual(Reception.shared.paywalls, [ReceptionPaywall(id: "support_chat", title: "Support offer")])
        for registration in [true, false] {
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: DeviceInfo.payload(
                identity: DeviceIdentity(), registration: registration)) as? [String: Any])
            XCTAssertEqual(body["paywalls"] as? [[String: String]], [["id": "support_chat", "title": "Support offer"]])
        }
        Reception.shared.paywalls = (0..<22).map { ReceptionPaywall(id: "offer-\($0)", title: "Offer") }
        XCTAssertEqual(Reception.shared.paywalls.count, 20)
        Reception.shared.paywalls = []
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: DeviceInfo.payload(identity: DeviceIdentity())) as? [String: Any])
        XCTAssertEqual((body["paywalls"] as? [[String: String]])?.count, 0)
    }

    func testMessageDecoding() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for kind in ["PAYWALL", "REVIEW", "FUTURE"] {
            let data = Data("""
            {"id":"message", "seq":1, "sender":"AGENT", "text":"Hello", "attachments":[],
             "createdAt":"2026-09-24T10:00:00Z", "kind":"\(kind)", "paywallId":"support_chat",
             "paywallTitle":"Support offer", "buttonLabel":"Claim 50% off", "actionClickedAt":"2026-09-24T10:01:00Z"}
            """.utf8)
            let message = try decoder.decode(Message.self, from: data)
            XCTAssertEqual(message.kind, kind)
            XCTAssertEqual(message.text, "Hello")
            XCTAssertEqual(message.paywallId, "support_chat")
            XCTAssertEqual(message.paywallTitle, "Support offer")
            XCTAssertEqual(message.buttonLabel, "Claim 50% off")
            XCTAssertEqual(message.actionClickedAt?.timeIntervalSince1970, 1_790_244_060)
            let nullData = Data(String(decoding: data, as: UTF8.self)
                .replacingOccurrences(of: "\"2026-09-24T10:01:00Z\"", with: "null").utf8)
            XCTAssertNil(try decoder.decode(Message.self, from: nullData).actionClickedAt)
        }
    }

    @MainActor
    func testTapGatingAndCachedPaywall() throws {
        let reception = Reception.shared
        let previous = (reception.paywalls, reception.onPaywall, reception.onEvent, reception.session)
        let store = DeviceStore(scope: UUID().uuidString, credentialStorage: .init(read: { _ in .missing }, save: { _, _ in true }, delete: { _ in true }))
        let session = DeviceSession(api: ReceptionAPI(appId: "app_abcdefghijklmnopqrstuv", baseURL: try XCTUnwrap(URL(string: "https://example.invalid"))), store: store)
        reception.session = session
        defer {
            session.invalidate()
            reception.paywalls = previous.0; reception.onPaywall = previous.1
            reception.onEvent = previous.2; reception.session = previous.3
        }
        let chat = ChatModel(session: session)
        var message = Message(id: "paywall", sender: "AGENT", text: "Offer", attachments: [], createdAt: Date(),
                              kind: "PAYWALL", paywallId: "support_chat", paywallTitle: "Support offer", buttonLabel: "Claim 50% off")
        var opened: [String] = []
        var events = 0
        reception.onEvent = { if case .paywallOpened = $0 { events += 1 } }
        reception.paywalls = [ReceptionPaywall(id: "support_chat", title: "Support offer")]
        reception.onPaywall = nil
        XCTAssertFalse(chat.canOpenPaywall(message))
        chat.openPaywall(message)
        reception.onPaywall = { opened.append($0) }
        message.paywallId = "unknown"
        XCTAssertFalse(chat.canOpenPaywall(message))
        chat.openPaywall(message)
        XCTAssertTrue(store.pendingActionClicks.isEmpty)
        XCTAssertTrue(opened.isEmpty)
        XCTAssertEqual(events, 0)
        message.paywallId = "support_chat"
        XCTAssertTrue(chat.canOpenPaywall(message))
        chat.isVisible = true
        chat.openPaywall(message)
        XCTAssertEqual(store.pendingActionClicks, ["paywall"])
        XCTAssertEqual(opened, ["support_chat"])
        XCTAssertEqual(events, 1)
        XCTAssertTrue(chat.isVisible)
        message.actionClickedAt = Date(timeIntervalSince1970: 100)
        store.chatCache.save([message])
        let cached = store.chatCache.load().first
        XCTAssertEqual(cached?.paywallId, message.paywallId)
        XCTAssertEqual(cached?.paywallTitle, message.paywallTitle)
        XCTAssertEqual(cached?.buttonLabel, message.buttonLabel)
        XCTAssertEqual(cached?.actionClickedAt, message.actionClickedAt)
    }

    @MainActor
    func testAvailabilityFiltersInRegisteredOrder() async {
        let restore = preserve()
        defer { restore() }
        let reception = Reception.shared
        reception.paywalls = offers
        XCTAssertEqual(reception.availablePaywalls, offers, "without a check every paywall is available")
        reception.paywallAvailability = { $0 != "b" }
        XCTAssertTrue(reception.availablePaywalls.isEmpty, "a new check starts from an empty list")
        await waitUntil { reception.availablePaywalls.map(\.id) == ["a", "c"] }
        XCTAssertEqual(reception.paywalls, offers)
        reception.paywallAvailability = nil
        XCTAssertEqual(reception.availablePaywalls, offers)
    }

    @MainActor
    func testRefreshKeepsListUnlessInvalidated() async {
        let restore = preserve()
        defer { restore() }
        let reception = Reception.shared
        let gate = Gate()
        var holds = false
        var started = 0
        reception.paywalls = offers
        reception.paywallAvailability = { id in
            started += 1
            if holds { await gate.wait() }
            return id != "c"
        }
        await waitUntil { reception.availablePaywalls.map(\.id) == ["a", "b"] }
        holds = true
        started = 0
        reception.refreshPaywalls()
        await waitUntil { started == 1 }
        XCTAssertEqual(reception.availablePaywalls.map(\.id), ["a", "b"], "same user: keep the list while checking")
        reception.refreshPaywalls(invalidate: true)
        XCTAssertTrue(reception.availablePaywalls.isEmpty, "subscription or user change: clear at once")
        reception.refreshPaywalls()
        XCTAssertTrue(reception.availablePaywalls.isEmpty, "a plain refresh keeps the invalidated list")
        holds = false
        gate.open()
        await waitUntil { reception.availablePaywalls.map(\.id) == ["a", "b"] }
    }

    @MainActor
    func testStaleCheckCannotOverwriteNewerResult() async {
        let restore = preserve()
        defer { restore() }
        let reception = Reception.shared
        let gate = Gate()
        var calls = 0
        var staleFinished = false
        reception.paywalls = [ReceptionPaywall(id: "a", title: "A")]
        // The first check ignores cancellation and answers late.
        reception.paywallAvailability = { _ in
            calls += 1
            guard calls == 1 else { return true }
            await gate.wait()
            staleFinished = true
            return false
        }
        await waitUntil { calls == 1 }
        reception.refreshPaywalls(invalidate: true)
        await waitUntil { reception.availablePaywalls.map(\.id) == ["a"] }
        XCTAssertFalse(staleFinished, "the newer check completes while the older one still hangs")
        gate.open()
        await waitUntil { staleFinished }
        XCTAssertEqual(reception.availablePaywalls.map(\.id), ["a"], "the late answer belongs to a replaced check")
    }

    @MainActor
    func testLogoutInvalidatesAndIgnoresLateAnswers() async throws {
        let restore = preserve()
        defer { restore() }
        let reception = Reception.shared
        let previousSession = reception.session
        let store = DeviceStore(scope: UUID().uuidString, credentialStorage: .init(read: { _ in .missing }, save: { _, _ in true }, delete: { _ in true }))
        let session = DeviceSession(api: ReceptionAPI(appId: "app_abcdefghijklmnopqrstuv", baseURL: try XCTUnwrap(URL(string: "https://example.invalid"))), store: store)
        reception.session = session
        defer { session.invalidate(); reception.session = previousSession }
        let gate = Gate()
        var subscribed = false
        var holds = false
        var lateFinished = false
        reception.paywalls = [ReceptionPaywall(id: "a", title: "A")]
        reception.paywallAvailability = { _ in
            guard holds else { return !subscribed }
            holds = false
            await gate.wait()
            lateFinished = true
            return true
        }
        await waitUntil { reception.availablePaywalls.map(\.id) == ["a"] }
        holds = true
        reception.refreshPaywalls()
        await waitUntil { !holds }
        subscribed = true
        reception.logout()
        XCTAssertTrue(reception.availablePaywalls.isEmpty, "logout clears at once")
        gate.open()
        await waitUntil { lateFinished }
        XCTAssertTrue(reception.availablePaywalls.isEmpty, "the previous user's answer is ignored")
    }

    @MainActor
    func testTitlesUpdateWhileNewIdsWaitForCheck() async {
        let restore = preserve()
        defer { restore() }
        let reception = Reception.shared
        let gate = Gate()
        var holds = false
        reception.paywalls = [ReceptionPaywall(id: "a", title: "A")]
        reception.paywallAvailability = { _ in
            if holds { await gate.wait() }
            return true
        }
        await waitUntil { reception.availablePaywalls.map(\.id) == ["a"] }
        holds = true
        reception.paywalls = [ReceptionPaywall(id: "a", title: "Renamed"), ReceptionPaywall(id: "b", title: "B")]
        XCTAssertEqual(reception.availablePaywalls, [ReceptionPaywall(id: "a", title: "Renamed")])
        gate.open()
        await waitUntil { reception.availablePaywalls.map(\.id) == ["a", "b"] }
    }

    @MainActor
    func testCardsFollowAvailability() async throws {
        let restore = preserve()
        defer { restore() }
        let reception = Reception.shared
        let previousHandler = reception.onPaywall
        defer { reception.onPaywall = previousHandler }
        let message = Message(id: "paywall", sender: "AGENT", text: "Offer", attachments: [], createdAt: Date(),
                              kind: "PAYWALL", paywallId: "a", paywallTitle: "A")
        let chat = ChatModel()
        reception.onPaywall = { _ in }
        reception.paywalls = offers
        XCTAssertTrue(chat.canOpenPaywall(message))
        reception.paywallAvailability = { $0 != "a" }
        await waitUntil { reception.availablePaywalls.map(\.id) == ["b", "c"] }
        XCTAssertFalse(chat.canOpenPaywall(message))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: DeviceInfo.payload(identity: DeviceIdentity())) as? [String: Any])
        XCTAssertEqual((body["paywalls"] as? [[String: String]])?.map { $0["id"] }, ["b", "c"])
    }

    private let offers = [ReceptionPaywall(id: "a", title: "A"), ReceptionPaywall(id: "b", title: "B"),
                          ReceptionPaywall(id: "c", title: "C")]

    @MainActor
    private func preserve() -> () -> Void {
        let reception = Reception.shared
        let previous = (reception.paywalls, reception.paywallAvailability)
        reception.paywallAvailability = nil
        reception.paywalls = []
        return {
            reception.paywallAvailability = nil
            reception.paywalls = previous.0
            reception.paywallAvailability = previous.1
        }
    }

    @MainActor
    private func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = Date().addingTimeInterval(2)
        while !condition() {
            guard Date() < deadline else { return XCTFail("condition not met within 2 seconds", file: file, line: line) }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }
}

@MainActor
private final class Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}
