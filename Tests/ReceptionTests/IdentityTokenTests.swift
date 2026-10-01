import XCTest
@testable import Reception

final class IdentityTokenTests: XCTestCase {
    /// Builds an unsigned test token around a raw JSON payload, so number spellings such as `1e3` survive.
    private func token(payload: String, padded: Bool = false) -> String {
        var encoded = Data(payload.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        if !padded { encoded = encoded.replacingOccurrences(of: "=", with: "") }
        return "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9." + encoded + ".c2lnbmF0dXJl"
    }

    private func userId(_ claim: String) -> String? {
        IdentityToken.userId(in: token(payload: #"{"user_id":\#(claim),"exp":1900000000}"#))
    }

    func testSharedUserIdVectors() {
        XCTAssertEqual(userId("42"), "42")
        XCTAssertEqual(userId("42.0"), "42")
        XCTAssertEqual(userId("1e3"), "1000")
        XCTAssertEqual(userId("-5"), "-5")
        XCTAssertEqual(userId("9007199254740991"), "9007199254740991")
        XCTAssertEqual(userId(#""42 ""#), "42 ")
        XCTAssertNil(userId("9007199254740992"))
        XCTAssertNil(userId("42.5"))
        XCTAssertNil(userId("true"))
        XCTAssertNil(userId(#""""#))
    }

    func testOtherUserIdClaims() {
        XCTAssertEqual(userId("-0"), "0")
        XCTAssertEqual(userId("-9007199254740991"), "-9007199254740991")
        XCTAssertNil(userId("-9007199254740992"))
        XCTAssertEqual(userId(#""   ""#), "   ")
        XCTAssertEqual(userId(#""user-ÄÖ-😀""#), "user-ÄÖ-😀")
        XCTAssertEqual(userId("\"" + String(repeating: "a", count: 255) + "\""), String(repeating: "a", count: 255))
        XCTAssertNil(userId("\"" + String(repeating: "a", count: 256) + "\""))
        XCTAssertNil(userId("\"" + String(repeating: "😀", count: 128) + "\""))
        for claim in ["false", "null", "[42]", #"{"id":42}"#, "1e400"] {
            XCTAssertNil(userId(claim), claim)
        }
        XCTAssertNil(IdentityToken.userId(in: token(payload: #"{"sub":"42","exp":1900000000}"#)))
    }

    func testTokenStructure() {
        XCTAssertEqual(IdentityToken.userId(in: token(payload: #"{"user_id":"~~~","exp":1}"#)), "~~~")
        XCTAssertEqual(IdentityToken.userId(in: token(payload: #"{"user_id":"ok~?","exp":1}"#, padded: true)), "ok~?")
        let valid = token(payload: #"{"user_id":"42"}"#)
        let parts = valid.split(separator: ".").map(String.init)
        for invalid in [parts[0] + "." + parts[1], valid + ".extra", parts[0] + ".." + parts[2],
                        parts[0] + ".%%%." + parts[2], token(payload: "[1,2]"), token(payload: "not json"), ""] {
            XCTAssertNil(IdentityToken.userId(in: invalid), invalid)
        }
        let long = token(payload: #"{"user_id":"42","pad":""# + String(repeating: "x", count: 3100) + #""}"#)
        XCTAssertGreaterThan(long.utf16.count, 4096)
        XCTAssertNil(IdentityToken.userId(in: long))
    }

    func testStagedTokenStartsUnsent() throws {
        let staged = try XCTUnwrap(IdentityToken(token(payload: #"{"user_id":7}"#)))
        XCTAssertEqual(staged.userId, "7")
        XCTAssertFalse(staged.sent)
        XCTAssertNil(IdentityToken("not.a.token"))
    }
}
