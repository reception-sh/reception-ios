import XCTest
@testable import Reception

@MainActor
final class DevicePayloadTests: XCTestCase {
    func testLinkSupportIsReportedAndSynchronized() throws {
        let reception = Reception.shared
        let previous = (LinkPolicy.main, reception.onLink)
        defer { LinkPolicy.main = previous.0; reception.onLink = previous.1 }
        // The app's own scheme comes first in Info.plist; third-party schemes that sort earlier must not push it out.
        let schemes = ["ZetaApp", "fb123", "zetaapp"] + (0..<23).map { "aaa\($0)" }
        LinkPolicy.main = LinkPolicy(infoDictionary: ["CFBundleURLTypes": [["CFBundleURLSchemes": schemes]]])
        reception.onLink = nil
        var body = try payload()
        let reported = try XCTUnwrap(body["urlSchemes"] as? [String])
        XCTAssertEqual(reported, ["zetaapp", "fb123"] + (0..<18).map { "aaa\($0)" })
        XCTAssertFalse(reported.contains("aaa18"))
        XCTAssertEqual(body["handlesLinks"] as? Bool, false)

        let store = DeviceStore(scope: UUID().uuidString, credentialStorage: .init(read: { _ in .missing }, save: { _, _ in true }, delete: { _ in true }))
        let session = DeviceSession(api: ReceptionAPI(appId: "app_abcdefghijklmnopqrstuv", baseURL: try XCTUnwrap(URL(string: "https://example.invalid"))), store: store)
        defer { session.invalidate() }
        session.synchronizedPaywalls = reception.availablePaywalls
        session.synchronizedLanguage = ReceptionLocalization.appLanguage
        session.synchronizedAppBadge = reception.updatesAppBadge
        session.synchronizedSubscribed = reception.paidAccess.current
        session.synchronizedHandlesLinks = false
        XCTAssertFalse(session.preferencesNeedSync)
        reception.onLink = { _ in true }
        XCTAssertTrue(session.preferencesNeedSync)
        body = try payload()
        XCTAssertEqual(body["handlesLinks"] as? Bool, true)
        session.synchronizedHandlesLinks = true
        XCTAssertFalse(session.preferencesNeedSync)
    }

    private func payload() throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: DeviceInfo.payload(identity: DeviceIdentity())) as? [String: Any])
    }
}
