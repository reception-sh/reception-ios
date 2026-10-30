import XCTest
@testable import Reception

@MainActor
final class PushPromptTests: XCTestCase {
    private func envelope(_ pushPrompt: String?) throws -> AppearanceEnvelope {
        let field = pushPrompt.map { #","pushPrompt":"\#($0)""# } ?? ""
        let json = #"{"schemaVersion":1,"revision":3,"appearance":{}\#(field)}"#
        return try JSONDecoder().decode(AppearanceEnvelope.self, from: Data(json.utf8))
    }

    func testAppearanceEnvelopeCarriesThePushPrompt() throws {
        XCTAssertNil(try envelope(nil).pushPrompt)
        XCTAssertEqual(try envelope("replies").pushPrompt.flatMap(PushPrompt.init(rawValue:)), .replies)
        XCTAssertEqual(try envelope("offers").pushPrompt.flatMap(PushPrompt.init(rawValue:)), .offers)
        XCTAssertEqual(try envelope("weekly").pushPrompt, "weekly")
        XCTAssertNil(try envelope("weekly").pushPrompt.flatMap(PushPrompt.init(rawValue:)))
        let null = #"{"schemaVersion":1,"revision":3,"appearance":{},"pushPrompt":null}"#
        XCTAssertNil(try JSONDecoder().decode(AppearanceEnvelope.self, from: Data(null.utf8)).pushPrompt)
    }

    func testCachedEnvelopeActivatesThePushPrompt() throws {
        let api = ReceptionAPI(appId: "app_abcdefghijklmnopqrstuv", baseURL: try XCTUnwrap(URL(string: "https://reception.test")))
        let cases: [(String?, PushPrompt?)] = [("offers", .offers), ("replies", .replies), ("weekly", nil), (nil, nil)]
        for (value, expected) in cases {
            let scope = "push-prompt-" + UUID().uuidString
            AppearanceCache(scope: scope).save(try envelope(value))
            let configuration = AppearanceConfiguration()
            configuration.configure(api: api, scope: scope)
            XCTAssertEqual(configuration.activePushPrompt, expected, value ?? "absent")
            XCTAssertNotNil(configuration.active)
        }
    }

    func testDeclinedCardSurvivesChatResetAndLogout() {
        let appScope = "push-declined-" + UUID().uuidString
        let storage = DeviceStore.CredentialStorage(read: { _ in .missing }, save: { _, _ in true }, delete: { _ in true })
        let store = DeviceStore(scope: appScope + "first", deviceScope: appScope, credentialStorage: storage)
        XCTAssertFalse(store.pushPromptDeclined)
        store.pushPromptDeclined = true
        store.pushActive = true
        store.resetChat(revision: 2)
        XCTAssertNil(store.renewed().pushActive)
        XCTAssertTrue(store.renewed().pushPromptDeclined)
        store.clear()
        // Logout continues in a new session namespace of the same App ID.
        XCTAssertTrue(DeviceStore(scope: appScope + "second", deviceScope: appScope, credentialStorage: storage).pushPromptDeclined)
        XCTAssertFalse(DeviceStore(scope: "other-" + UUID().uuidString, credentialStorage: storage).pushPromptDeclined)
    }

    func testPushEligibilityFromDeviceUpdateAndConversation() async throws {
        let f = try LimitReleaseFixture()
        defer { f.finish() }
        StubURLProtocol.install { [script = f.script] request in
            request.path == "/v1/devices/me" ? .init(body: #"{"verifiedUserId":null,"push":true}"#) : script.reply(request)
        }
        try await f.session.update()
        XCTAssertEqual(f.session.store.pushActive, true)

        // Older services omit the field; the stored value stays.
        StubURLProtocol.install { [script = f.script] in script.reply($0) }
        f.script.state.withLock { $0.conversation = .init(body: #"{"conversation":null,"messages":[]}"#) }
        await f.chat.load()
        XCTAssertEqual(f.session.store.pushActive, true)

        f.script.state.withLock { $0.conversation = .init(body: #"{"conversation":null,"messages":[],"push":false}"#) }
        await f.chat.load()
        XCTAssertEqual(f.session.store.pushActive, false)
    }

    func testSlotFollowsTheChatState() throws {
        let f = try LimitReleaseFixture()
        defer { f.finish() }
        f.chat.messages = [Message(id: "m1", sender: "USER", text: "Hi", attachments: [], createdAt: Date(), status: .sent)]
        f.chat.notificationAuthorization = .authorized
        XCTAssertEqual(f.chat.pushPromptSlot, .none)
        f.session.store.pushActive = true
        XCTAssertEqual(f.chat.pushPromptSlot, .status)
        // The fixture turns remote appearance off, so no card shows even while iOS has not asked.
        f.chat.notificationAuthorization = .notDetermined
        XCTAssertEqual(f.chat.pushPromptSlot, .none)
    }

    func testEveryLanguageHasTheNotificationTexts() throws {
        let keys = ["Get a notification when we reply.", "Get notifications for replies, offers and updates.",
                    "Continue", "No thanks", "You'll get a notification when we reply."]
        let missing = "\u{0}missing"
        for language in ReceptionLocalization.supportedLanguages {
            let url = try XCTUnwrap(ReceptionResources.bundle.url(forResource: language, withExtension: "lproj"), language)
            let bundle = try XCTUnwrap(Bundle(url: url), language)
            for key in keys {
                let value = bundle.localizedString(forKey: key, value: missing, table: "Localizable")
                XCTAssertNotEqual(value, missing, "\(language): \(key)")
                XCTAssertFalse(value.trimmingCharacters(in: .whitespaces).isEmpty, "\(language): \(key)")
            }
        }
    }
}
