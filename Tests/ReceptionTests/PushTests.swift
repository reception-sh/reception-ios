import XCTest
import UserNotifications
@testable import Reception

final class PushTests: XCTestCase {
    func testOnlyExistingPermissionAllowsRegistration() {
        for status: UNAuthorizationStatus in [.authorized, .provisional, .ephemeral] {
            XCTAssertTrue(PushAuthorization.allowsRegistration(status))
        }
        for status: UNAuthorizationStatus in [.denied, .notDetermined] {
            XCTAssertFalse(PushAuthorization.allowsRegistration(status))
        }
    }

    func testRoutingKeepsTheExistingPayloadContract() {
        for payload: [AnyHashable: Any] in [[:], ["reception": "thread"],
            ["reception": [:]], ["reception": ["conversationId": ""]],
            ["reception": ["conversationId": 1]]] {
            XCTAssertNil(Reception.pushConversationId(payload))
        }
        XCTAssertEqual(Reception.pushConversationId(["reception": ["conversationId": "thread"]]), "thread")
    }

    @MainActor func testUnrelatedForegroundNotificationsKeepHostPolicy() async {
        let options = await Reception.shared.notificationPresentationOptions(userInfo: ["other": true])
        XCTAssertNil(options)
    }

    @MainActor func testForegroundReceiptDoesNotOpenChat() async {
        let options = await Reception.shared.notificationPresentationOptions(
            userInfo: ["reception": ["conversationId": "thread"]])
        XCTAssertEqual(options, [.banner, .sound])
        XCTAssertFalse(Reception.shared.isChatOpen)
    }
}
