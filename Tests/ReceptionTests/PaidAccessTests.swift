import XCTest
@testable import Reception

@MainActor
final class PaidAccessTests: XCTestCase {
    func testOriginalTransactionIdsAreSortedAndCapped() {
        let access = PaidAccess()
        XCTAssertNil(access.current)
        XCTAssertNil(access.transactionIds, "nothing is reported before the first check")

        access.apply([2_000_000_123, 12, 7])
        XCTAssertEqual(access.current, true)
        XCTAssertEqual(access.transactionIds, ["7", "12", "2000000123"], "sorted by value, as decimal strings")

        access.apply(Set((1...30).map { UInt64($0) }))
        XCTAssertEqual(access.transactionIds?.count, 20)
        XCTAssertEqual(access.transactionIds?.first, "1")

        access.apply([])
        XCTAssertEqual(access.current, false)
        XCTAssertEqual(access.transactionIds, [], "an empty list is sent; the service keeps the ids it knew")
    }

    func testDevicePayloadCarriesTransactionIdsAndAChangeSynchronizes() throws {
        let reception = Reception.shared
        let previous = reception.session
        let store = DeviceStore(scope: UUID().uuidString, credentialStorage: .init(read: { _ in .missing }, save: { _, _ in true }, delete: { _ in true }))
        let session = DeviceSession(api: ReceptionAPI(appId: "app_abcdefghijklmnopqrstuv", baseURL: try XCTUnwrap(URL(string: "https://example.invalid"))), store: store)
        reception.session = session
        defer {
            reception.paidAccess.apply([])
            session.invalidate()
            reception.session = previous
        }

        reception.paidAccess.apply([42, 7])
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: DeviceInfo.payload(identity: DeviceIdentity())) as? [String: Any])
        XCTAssertEqual(body["subscribed"] as? Bool, true)
        XCTAssertEqual(body["transactionIds"] as? [String], ["7", "42"])

        session.synchronizedPaywalls = reception.availablePaywalls
        session.synchronizedLanguage = ReceptionLocalization.appLanguage
        session.synchronizedAppBadge = reception.updatesAppBadge
        session.synchronizedSubscribed = reception.paidAccess.current
        session.synchronizedTransactionIds = reception.paidAccess.transactionIds
        session.synchronizedScreens = ScreenLink.report(reception.screens)
        XCTAssertFalse(session.preferencesNeedSync)
        reception.paidAccess.apply([42, 7, 99])
        XCTAssertTrue(session.preferencesNeedSync, "a new purchase is sent although paid access did not change")
    }
}
