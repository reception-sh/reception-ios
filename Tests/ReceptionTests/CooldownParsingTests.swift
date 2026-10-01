import XCTest
@testable import Reception

/// The optional `error.retryScope` contract: known, unknown and missing scopes, and every Retry-After shape.
final class CooldownParsingTests: XCTestCase {
    private func response(_ status: Int, retryAfter: String? = nil) throws -> HTTPURLResponse {
        try XCTUnwrap(HTTPURLResponse(url: try XCTUnwrap(URL(string: "https://reception.test/v1/x")), statusCode: status,
                                      httpVersion: "HTTP/1.1", headerFields: retryAfter.map { ["Retry-After": $0] }))
    }

    func testNamedScopeWinsOverTheRoute() throws {
        for scope in RetryScope.allCases {
            let wait = ReceptionAPI.wait(try response(429, retryAfter: "37"), named: scope.rawValue,
                                         path: "uploads", method: "POST", authenticated: true)
            XCTAssertEqual(wait.seconds, 37)
            XCTAssertEqual(wait.scope, scope, "A general limit during an upload must not become an uploads wait")
        }
    }

    func testMissingOrUnknownScopeFallsBackToTheRoute() throws {
        let routes: [(String, String, Bool, RetryScope?)] = [
            ("conversation/messages", "POST", true, .messages), ("uploads", "POST", true, .uploads),
            ("devices", "POST", false, .session), ("devices/me/token", "POST", false, .session),
            ("conversation/events", "GET", true, .stream), ("conversation", "GET", true, .requests),
            ("conversation/messages?after=4", "GET", true, .requests), ("devices/me", "PATCH", true, .requests),
            ("appearance", "GET", false, nil)
        ]
        for named in [nil, "future", ""] {
            for (path, method, authenticated, expected) in routes {
                let wait = ReceptionAPI.wait(try response(429, retryAfter: "5"), named: named,
                                             path: path, method: method, authenticated: authenticated)
                XCTAssertEqual(wait.scope, expected, "\(method) \(path) with \(named ?? "no scope")")
                XCTAssertEqual(wait.seconds, 5)
            }
        }
    }

    func testRetryAfterIsCappedAtOneDayAndInvalidValuesStartNoCooldown() throws {
        let valid = ["0": 1, "1": 1, "301": 301, "86400": 86_400, "86401": 86_400, "999999999": 86_400, " 42 ": 42]
        for (header, seconds) in valid {
            let wait = ReceptionAPI.wait(try response(429, retryAfter: header), named: "messages",
                                         path: "conversation/messages", method: "POST", authenticated: true)
            XCTAssertEqual(wait.seconds, seconds, header)
            XCTAssertEqual(wait.scope, .messages, header)
        }
        for header in [nil, "soon", "-1", "1.5", "Wed, 21 Oct 2026 07:28:00 GMT"] {
            let wait = ReceptionAPI.wait(try response(429, retryAfter: header), named: "messages",
                                         path: "conversation/messages", method: "POST", authenticated: true)
            XCTAssertNil(wait.seconds, header ?? "missing")
            XCTAssertNil(wait.scope, "Without a usable Retry-After the ordinary backoff applies")
        }
    }

    func testOnlyAScoped503WithRetryAfterIsACooldown() throws {
        let capacity = ReceptionAPI.wait(try response(503, retryAfter: "2"), named: "uploads",
                                         path: "conversation/messages", method: "POST", authenticated: true)
        XCTAssertEqual(capacity.seconds, 2)
        XCTAssertEqual(capacity.scope, .uploads)
        for (named, header) in [(nil, "2"), ("uploads", nil), ("future", "2")] as [(String?, String?)] {
            let wait = ReceptionAPI.wait(try response(503, retryAfter: header), named: named,
                                         path: "uploads", method: "POST", authenticated: true)
            XCTAssertNil(wait.seconds)
            XCTAssertNil(wait.scope, "An unscoped or unusable 503 keeps network backoff")
        }
        XCTAssertNil(ReceptionAPI.wait(try response(500, retryAfter: "2"), named: "uploads",
                                       path: "uploads", method: "POST", authenticated: true).scope)
    }

    func testDeletionAndRevocationNeverWaitForOrStartCooldowns() throws {
        for (path, method) in [("devices/me", "DELETE"), ("devices/me/logout", "POST")] {
            XCTAssertEqual(RetryScope.gates(path, method: method, authenticated: false), [])
            let wait = ReceptionAPI.wait(try response(429, retryAfter: "60"), named: "requests",
                                         path: path, method: method, authenticated: false)
            XCTAssertEqual(wait.seconds, 60, "The value still paces the revocation queue's backoff")
            XCTAssertNil(wait.scope)
        }
        XCTAssertEqual(RetryScope.gates("conversation/messages", method: "POST", authenticated: true, photos: true),
                       [.messages, .uploads, .requests])
        XCTAssertEqual(RetryScope.gates("devices", method: "POST", authenticated: false), [.session])
    }

    func testStorageRetryAfterStaysWithinTheOldBackoffBound() throws {
        XCTAssertEqual(ReceptionAPI.retryAfter(try response(429, retryAfter: "86400"), maximum: 300), 300)
        XCTAssertEqual(ReceptionAPI.retryAfter(try response(429, retryAfter: "86400")), 86_400)
        XCTAssertNil(ReceptionAPI.retryAfter(try response(503, retryAfter: "20")))
    }

    func testMalformedScopeKeepsCodeAndResetRevision() throws {
        let bodies = [
            #"{"error":{"code":"chat_reset","message":"Reset","resetRevision":3,"retryScope":42}}"#,
            #"{"error":{"code":"chat_reset","message":"Reset","resetRevision":3,"retryScope":["messages"]}}"#,
            #"{"error":{"code":"chat_reset","message":"Reset","resetRevision":3,"retryScope":"future"}}"#,
            #"{"error":{"code":"chat_reset","message":"Reset","resetRevision":3}}"#
        ]
        for body in bodies {
            let envelope = try JSONDecoder().decode(ReceptionAPI.ErrorEnvelope.self, from: Data(body.utf8))
            XCTAssertEqual(envelope.error.code, "chat_reset", body)
            XCTAssertEqual(envelope.error.resetRevision, 3, body)
        }
        let named = try JSONDecoder().decode(ReceptionAPI.ErrorEnvelope.self,
            from: Data(#"{"error":{"code":"rate_limited","message":"Wait","retryScope":"stream"}}"#.utf8))
        XCTAssertEqual(named.error.retryScope, "stream")
    }
}
