import XCTest
@testable import Reception

final class UserIdentityTests: XCTestCase {
    private func token(_ userId: String) throws -> IdentityToken {
        let payload = try JSONSerialization.data(withJSONObject: ["user_id": userId])
            .base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return try XCTUnwrap(IdentityToken("e30.\(payload).signature"))
    }

    func testCanonicallyEquivalentVerifiedIdsRequireUserSwitch() throws {
        for (stored, incoming) in [("\u{00e9}", "e\u{0301}"), ("e\u{0301}", "\u{00e9}")] {
            let identity = try token(incoming)
            XCTAssertEqual(Array(identity.userId.utf8), Array(incoming.utf8), "Decoding must preserve the ID bytes")
            XCTAssertFalse(identity.matchesUser(verifiedUserId: stored, unverifiedUserId: nil))
            XCTAssertFalse(identity.matchesUser(verifiedUserId: stored, unverifiedUserId: incoming))
        }
    }

    func testCanonicallyEquivalentUnverifiedIdsRequireUserSwitch() throws {
        for (stored, incoming) in [("\u{00e9}", "e\u{0301}"), ("e\u{0301}", "\u{00e9}")] {
            XCTAssertFalse(try token(incoming).matchesUser(verifiedUserId: nil, unverifiedUserId: stored))
        }
    }

    func testIdenticalIdsRetainTheirSession() throws {
        for userId in ["\u{00e9}", "e\u{0301}", "42 ", "42", "user-😀"] {
            let identity = try token(userId)
            XCTAssertTrue(identity.matchesUser(verifiedUserId: userId, unverifiedUserId: nil))
            XCTAssertTrue(identity.matchesUser(verifiedUserId: userId, unverifiedUserId: "other"))
            XCTAssertTrue(identity.matchesUser(verifiedUserId: nil, unverifiedUserId: userId))
        }
    }

    func testAnonymousSessionCanBeVerifiedAndDistinctIdsRequireSwitch() throws {
        let identity = try token("42")
        XCTAssertTrue(identity.matchesUser(verifiedUserId: nil, unverifiedUserId: nil))
        XCTAssertFalse(identity.matchesUser(verifiedUserId: "42 ", unverifiedUserId: nil))
        XCTAssertFalse(identity.matchesUser(verifiedUserId: nil, unverifiedUserId: "42 "))
    }

    func testStagedIdentityRequiresAnExactMatchUntilVerificationFinishes() throws {
        let identity = try token("e\u{0301}")
        XCTAssertFalse(identity.matchesUser(verifiedUserId: nil, unverifiedUserId: nil, stagedUserId: "\u{00e9}"))
        XCTAssertTrue(identity.matchesUser(verifiedUserId: nil, unverifiedUserId: nil, stagedUserId: "e\u{0301}"))
        XCTAssertFalse(identity.matchesUser(verifiedUserId: nil, unverifiedUserId: "other", stagedUserId: "e\u{0301}"))
    }
}
