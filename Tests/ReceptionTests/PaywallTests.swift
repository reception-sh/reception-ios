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

    @MainActor
    func testSourceAndProductsAreSentWhenProvided() throws {
        let previous = Reception.shared.paywalls
        defer { Reception.shared.paywalls = previous }
        Reception.shared.paywalls = [ReceptionPaywall(id: "main", title: "Main", source: .revenueCat, products: [
            .init(id: " pro_yearly ", price: "$59.99", period: "P1Y", trial: "P1W"),
            .init(id: "pro_monthly", price: " ", period: "monthly"),
            .init(id: "")
        ] + (0..<12).map { .init(id: "extra_\($0)") })]
        let paywall = try XCTUnwrap(Reception.shared.paywalls.first)
        XCTAssertEqual(paywall.products.count, 9)
        XCTAssertEqual(paywall.products.prefix(2), [.init(id: "pro_yearly", price: "$59.99", period: "P1Y", trial: "P1W"), .init(id: "pro_monthly")])
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: DeviceInfo.payload(identity: DeviceIdentity())) as? [String: Any])
        let entry = try XCTUnwrap((body["paywalls"] as? [[String: Any]])?.first)
        XCTAssertEqual(entry["source"] as? String, "revenuecat")
        XCTAssertEqual((entry["products"] as? [[String: String]])?.first, ["id": "pro_yearly", "price": "$59.99", "period": "P1Y", "trial": "P1W"])
        XCTAssertEqual((entry["products"] as? [[String: String]])?[1], ["id": "pro_monthly"])
    }

    @MainActor
    func testUnknownSourcesAreSentAndInvalidOnesDropped() throws {
        let previous = Reception.shared.paywalls
        defer { Reception.shared.paywalls = previous }
        Reception.shared.paywalls = [
            ReceptionPaywall(id: "a", title: "A", source: .adapty),
            ReceptionPaywall(id: "b", title: "B", source: .init(rawValue: "future-vendor")),
            ReceptionPaywall(id: "c", title: "C", source: .init(rawValue: "Not A Slug!"))
        ]
        XCTAssertEqual(Reception.shared.paywalls.map(\.source), [.adapty, .init(rawValue: "future-vendor"), nil])
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: DeviceInfo.payload(identity: DeviceIdentity())) as? [String: Any])
        XCTAssertEqual((body["paywalls"] as? [[String: Any]])?.map { $0["source"] as? String }, ["adapty", "future-vendor", nil])
    }

    @MainActor
    func testInfoOnlyPaywallsAreAlwaysListedAndNeverOpen() async throws {
        let reception = Reception.shared
        let previous = (reception.paywalls, reception.paywallAvailability, reception.onPaywall)
        defer { reception.paywalls = previous.0; reception.paywallAvailability = previous.1; reception.onPaywall = previous.2 }
        reception.onPaywall = { _ in }
        reception.paywalls = [ReceptionPaywall(id: "card", title: "Card"), ReceptionPaywall(id: "info", title: "Info", presentable: false)]
        reception.paywallAvailability = { _ in false }
        for _ in 0..<50 where reception.availablePaywalls.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(reception.availablePaywalls.map(\.id), ["info"])
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: DeviceInfo.payload(identity: DeviceIdentity())) as? [String: Any])
        XCTAssertEqual((body["paywalls"] as? [[String: Any]])?.first?["presentable"] as? Bool, false)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let message = try decoder.decode(Message.self, from: Data("""
        {"id":"m", "seq":1, "sender":"AGENT", "text":"", "attachments":[], "createdAt":"2026-09-24T10:00:00Z", "kind":"PAYWALL", "paywallId":"info"}
        """.utf8))
        XCTAssertFalse(ChatModel(session: nil).canOpenPaywall(message))
    }

    func testOriginalInitializerStaysReferenceable() {
        // Apps on 1.3 may pass the initializer itself; default arguments would not apply to such a reference.
        let make: (String, String) -> ReceptionPaywall = ReceptionPaywall.init
        XCTAssertEqual(make("plans", "Plans"), ReceptionPaywall(id: "plans", title: "Plans", source: nil))
        XCTAssertTrue(make("plans", "Plans").presentable)
    }

    @MainActor
    func testProductsStayWithinTheRequestBudget() throws {
        let previous = Reception.shared.paywalls
        defer { Reception.shared.paywalls = previous }
        let products = (0..<10).map { ReceptionPaywall.Product(id: String(repeating: "p", count: 99) + "\($0)", price: String(repeating: "¥", count: 40), period: "P1Y", trial: "P1W") }
        Reception.shared.paywalls = (0..<20).map { ReceptionPaywall(id: "offer-\($0)", title: String(repeating: "é", count: 60), source: .app, products: products) }
        XCTAssertEqual(Reception.shared.paywalls.reduce(0) { $0 + $1.products.count }, ReceptionPaywall.productBudget)
        XCTAssertEqual(Reception.shared.paywalls.count, 20)
        XCTAssertLessThan(try DeviceInfo.payload(identity: DeviceIdentity()).count, 32 * 1024)
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
