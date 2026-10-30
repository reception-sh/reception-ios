import XCTest
import UserNotifications
@testable import Reception

final class PushPromptDecisionTests: XCTestCase {
    private func resolve(prompt: PushPrompt? = .replies, authorization: UNAuthorizationStatus? = .notDetermined,
                         declined: Bool = false, answered: Bool = false, lastSender: String? = "USER",
                         lastFailed: Bool = false, canWrite: Bool = true, pushActive: Bool? = nil,
                         hidesStatus: Bool = false) -> PushPromptSlot {
        PushPromptDecision.resolve(prompt: prompt, authorization: authorization, declined: declined, answered: answered,
                                   lastSender: lastSender, lastFailed: lastFailed, canWrite: canWrite,
                                   pushActive: pushActive, hidesStatus: hidesStatus)
    }

    func testHiddenStatusLineLeavesTheCard() {
        XCTAssertEqual(resolve(authorization: .authorized, pushActive: true, hidesStatus: true), .none)
        XCTAssertEqual(resolve(hidesStatus: true), .card(.replies))
    }

    func testNothingShowsUnderAFailedMessage() {
        XCTAssertEqual(resolve(lastFailed: true), .none)
        XCTAssertEqual(resolve(authorization: .authorized, lastFailed: true, pushActive: true), .none)
    }

    func testNothingShowsWhileThisDeviceCannotWrite() {
        XCTAssertEqual(resolve(canWrite: false), .none)
        XCTAssertEqual(resolve(authorization: .authorized, canWrite: false, pushActive: true), .none)
    }

    func testNothingShowsUnlessThePersonWroteLast() {
        for sender: String? in ["AGENT", "SYSTEM", nil] {
            XCTAssertEqual(resolve(lastSender: sender), .none)
            XCTAssertEqual(resolve(authorization: .authorized, lastSender: sender, pushActive: true), .none)
        }
    }

    func testCardOffersTheDashboardPromptWhileIOSHasNotAsked() {
        XCTAssertEqual(resolve(prompt: .replies), .card(.replies))
        XCTAssertEqual(resolve(prompt: .offers), .card(.offers))
    }

    func testCardNeedsAPromptAndAnUnansweredPermission() {
        XCTAssertEqual(resolve(prompt: nil), .none)
        XCTAssertEqual(resolve(authorization: nil), .none)
        XCTAssertEqual(resolve(declined: true), .none)
        XCTAssertEqual(resolve(answered: true), .none)
        XCTAssertEqual(resolve(authorization: .denied), .none)
        XCTAssertEqual(resolve(authorization: .denied, pushActive: true), .none)
    }

    func testStatusLineNeedsPermissionAndAWorkingPush() {
        XCTAssertEqual(resolve(authorization: .authorized, pushActive: true), .status)
        XCTAssertEqual(resolve(authorization: .authorized, pushActive: false), .none)
        XCTAssertEqual(resolve(authorization: .authorized, pushActive: nil), .none)
        XCTAssertEqual(resolve(authorization: .provisional, pushActive: true), .status)
        XCTAssertEqual(resolve(authorization: .ephemeral, pushActive: true), .status)
    }

    func testStatusLineDoesNotDependOnTheDashboardPrompt() {
        XCTAssertEqual(resolve(prompt: nil, authorization: .authorized, pushActive: true), .status)
        XCTAssertEqual(resolve(authorization: .authorized, declined: true, answered: true, pushActive: true), .status)
    }

    func testAnsweredCardWaitsForTheNewPermission() {
        XCTAssertEqual(resolve(answered: true, pushActive: true), .none)
    }
}
