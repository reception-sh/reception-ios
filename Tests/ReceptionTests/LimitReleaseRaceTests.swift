import XCTest
@testable import Reception

@MainActor
final class LimitReleaseRaceTests: XCTestCase {
    func testFreedQuotaNeverOverridesBlockedOrVerificationPermission() async throws {
        for device in [#"{"blocked":true,"verificationRequired":false}"#,
                       #"{"blocked":false,"verificationRequired":true}"#] {
            let f = try LimitReleaseFixture()
            f.session.cooldowns.impose(.messages, seconds: 3600)
            f.held("held")
            f.script.state.withLock {
                $0.conversation = .init(body: "{\"conversation\":null,\"messages\":[],\"device\":\(device),\"limits\":{\"messages\":0}}")
            }
            await f.chat.load(recheckLimits: true)
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertNil(f.session.cooldowns.blocking([.messages]))
            XCTAssertEqual(f.posts, [])
            XCTAssertTrue(f.chat.messages[0].awaitsManualRetry)
            f.finish()
        }
    }

    func testDelayedAnswerCannotClearANewerRejectionWithTheSameDeadline() async throws {
        let f = try LimitReleaseFixture()
        let gate = StubURLProtocol.Gate()
        defer { gate.release(); f.finish() }
        f.session.cooldowns.impose(.messages, seconds: 3600)
        f.held("held")
        f.script.state.withLock { $0.conversation.gate = gate }
        let load = Task { await f.chat.load(recheckLimits: true) }
        try await f.waitUntil { StubURLProtocol.requests.contains { $0.query == "limits=1" } }
        f.session.cooldowns.impose(.messages, seconds: 3600)
        gate.release()
        await load.value
        XCTAssertNotNil(f.session.cooldowns.blocking([.messages]))
        XCTAssertEqual(f.posts, [])
    }

    func testMissingResultAndInternalLoadsDoNotClearWaitsOrBypassCheckSpacing() async throws {
        let f = try LimitReleaseFixture()
        defer { f.finish() }
        f.session.cooldowns.impose(.messages, seconds: 3600)
        f.held("held")
        await f.chat.load()
        XCTAssertNotNil(f.session.cooldowns.blocking([.messages]), "An unsolicited limits field is ignored")
        XCTAssertFalse(StubURLProtocol.requests.contains { $0.query == "limits=1" })

        f.script.state.withLock { $0.conversation = .init(body: #"{"conversation":null,"messages":[]}"#) }
        await f.chat.load(recheckLimits: true)
        f.script.state.withLock { $0.conversation = .init(body: #"{"conversation":null,"messages":[],"limits":{"messages":0}}"#) }
        await f.chat.load(recheckLimits: true)
        XCTAssertNotNil(f.session.cooldowns.blocking([.messages]))
        XCTAssertEqual(StubURLProtocol.requests.filter { $0.query == "limits=1" }.count, 1)
        XCTAssertEqual(f.posts, [])
    }

    func testClosingDuringTheGetDiscardsItsRelease() async throws {
        let f = try LimitReleaseFixture()
        let gate = StubURLProtocol.Gate()
        defer { gate.release(); f.finish() }
        f.session.cooldowns.impose(.messages, seconds: 3600)
        f.held("held")
        f.script.state.withLock { $0.conversation.gate = gate }
        let load = Task { await f.chat.load(recheckLimits: true) }
        try await f.waitUntil { StubURLProtocol.requests.contains { $0.query == "limits=1" } }
        f.chat.isVisible = false
        f.chat.stopPolling()
        gate.release()
        await load.value
        XCTAssertNotNil(f.session.cooldowns.blocking([.messages]))
        XCTAssertEqual(f.posts, [])
    }

    func testAReplacedSessionRejectsTheOldRelease() async throws {
        let f = try LimitReleaseFixture()
        let gate = StubURLProtocol.Gate()
        defer { gate.release(); f.finish() }
        f.session.cooldowns.impose(.messages, seconds: 3600)
        f.held("old-identity")
        f.script.state.withLock { $0.conversation.gate = gate }
        let load = Task { await f.chat.load(recheckLimits: true) }
        try await f.waitUntil { StubURLProtocol.requests.contains { $0.query == "limits=1" } }
        let replacement = DeviceSession(api: f.session.api, store: DeviceStore(scope: "replacement-" + UUID().uuidString,
            credentialStorage: .init(read: { _ in .missing }, save: { _, _ in true }, delete: { _ in true })))
        defer { replacement.invalidate() }
        Reception.shared.session = replacement
        gate.release()
        await load.value
        XCTAssertNotNil(f.session.cooldowns.blocking([.messages]))
        XCTAssertNil(replacement.cooldowns.blocking([.messages]))
        XCTAssertEqual(f.posts, [])
    }

    func testFailedGetKeepsTheWaitAndSpendsTheCheckInterval() async throws {
        let f = try LimitReleaseFixture()
        defer { f.finish() }
        f.session.cooldowns.impose(.messages, seconds: 3600)
        f.held("held")
        f.script.state.withLock { $0.conversation = .init(networkError: .notConnectedToInternet) }
        await f.chat.load(recheckLimits: true)
        XCTAssertNotNil(f.session.cooldowns.blocking([.messages]))
        XCTAssertTrue(f.session.cooldowns.beginRecheck().isEmpty)
        XCTAssertEqual(f.posts, [])
    }

    func testShortenedLongWaitDoesNotStartAnAutomaticTimerResend() async throws {
        let f = try LimitReleaseFixture()
        defer { f.finish() }
        f.session.cooldowns.impose(.messages, seconds: 3600)
        f.held("held")
        f.script.state.withLock { $0.conversation = .init(body: #"{"conversation":null,"messages":[],"limits":{"messages":30}}"#) }
        await f.chat.load(recheckLimits: true)
        XCTAssertFalse(f.session.cooldowns.blocking([.messages])?.automatic ?? true)
        f.time.now.addTimeInterval(31)
        f.chat.cooldownsChanged()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(f.posts, [])
        await f.chat.load(recheckLimits: true)
        try await f.waitUntil { f.posts == ["held"] }
    }
}
