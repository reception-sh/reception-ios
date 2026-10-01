import XCTest
@testable import Reception

@MainActor
final class LimitReleaseTests: XCTestCase {
    func testActual429BecomesEligibleAndOpeningResendsOnceInOrder() async throws {
        let f = try LimitReleaseFixture()
        defer { f.finish() }
        f.script.state.withLock { $0.sends = [LimitReleaseFixture.Script.limited("messages")] }
        let first = f.held("first")
        f.chat.messages[0].status = .sending
        f.chat.messages[0].retryAfterLimitRelease = false
        f.chat.submit(first, userInitiated: true)
        await f.chat.sends[first]?.value
        XCTAssertTrue(f.chat.messages[0].retryAfterLimitRelease, "A real 429, not just a local gate, records the intent")
        f.held("second")
        f.chat.composer.text = "Unsent draft"

        await f.chat.load(recheckLimits: true)
        try await f.waitUntil { f.chat.messages.allSatisfy { $0.status == .sent } }
        XCTAssertEqual(f.posts, ["first", "first", "second"])
        XCTAssertEqual(f.chat.messages.count, 2)
        XCTAssertEqual(f.chat.composer.text, "Unsent draft")
        XCTAssertEqual(StubURLProtocol.requests.filter { $0.query == "limits=1" }.count, 1)
        await f.chat.load(recheckLimits: true)
        XCTAssertEqual(f.posts, ["first", "first", "second"])
        XCTAssertEqual(StubURLProtocol.requests.filter { $0.query == "limits=1" }.count, 1)
    }

    func testCancelAndOrdinaryFailuresStayManualAcrossCacheRestore() async throws {
        let f = try LimitReleaseFixture()
        defer { f.finish() }
        f.session.cooldowns.impose(.messages, seconds: 3600)
        f.held("cancelled")
        f.chat.cancelAutomaticRetry(messageId: "cancelled")
        f.held("network-failure", eligible: false)
        f.held("eligible")
        f.chat.messages = f.session.store.chatCache.load()

        await f.chat.load(recheckLimits: true)
        try await f.waitUntil { f.posts == ["eligible"] }
        XCTAssertFalse(f.chat.messages.first { $0.id == "cancelled" }?.retryAfterLimitRelease ?? true)
        XCTAssertEqual(f.chat.messages.filter { $0.status == .failed }.map(\.id), ["cancelled", "network-failure"])
    }

    func testAlreadyConfirmedMessageMergesBeforeAnyResend() async throws {
        let f = try LimitReleaseFixture()
        defer { f.finish() }
        f.session.cooldowns.impose(.messages, seconds: 3600)
        f.held("confirmed")
        f.script.state.withLock {
            $0.conversation = .init(body: "{\"conversation\":null,\"messages\":[\(LimitReleaseFixture.Script.message("confirmed", seq: 1))],\"limits\":{\"messages\":0,\"uploads\":0}}")
        }
        await f.chat.load(recheckLimits: true)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(f.posts, [])
        XCTAssertEqual(f.chat.messages.count, 1)
        XCTAssertEqual(f.chat.messages.first?.status, .sent)
    }

    func testPhotoWaitKeepsPhotosHeldWhileReleasedTextResends() async throws {
        let f = try LimitReleaseFixture()
        defer { f.finish() }
        f.session.cooldowns.impose(.messages, seconds: 3600)
        f.session.cooldowns.impose(.uploads, seconds: 3600)
        f.held("photo", photos: true)
        f.held("text")
        f.script.state.withLock { $0.conversation = .init(body: #"{"conversation":null,"messages":[],"limits":{"messages":0,"uploads":600}}"#) }
        await f.chat.load(recheckLimits: true)
        try await f.waitUntil { f.posts == ["text"] }
        XCTAssertEqual(f.chat.messages.first { $0.id == "photo" }?.status, .failed)
        XCTAssertEqual(f.chat.messages.first { $0.id == "photo" }?.images.count, 1)

        f.time.now.addTimeInterval(60)
        f.script.state.withLock { $0.conversation = .init(body: #"{"conversation":null,"messages":[],"limits":{"messages":0,"uploads":0}}"#) }
        await f.chat.load(recheckLimits: true)
        try await f.waitUntil { f.posts == ["text", "photo"] }
    }

    func testFirstNewFailureStopsReleasedBatchAndDoesNotBecomeAnOrdinaryRetryLoop() async throws {
        for reply in [LimitReleaseFixture.Script.limited("messages", seconds: 1),
                      StubURLProtocol.Reply(networkError: .notConnectedToInternet)] {
            let f = try LimitReleaseFixture()
            f.session.cooldowns.impose(.messages, seconds: 3600)
            f.held("first"); f.held("second")
            f.script.state.withLock { $0.sends = [reply] }
            await f.chat.load(recheckLimits: true)
            try await f.waitUntil { f.posts == ["first"] && f.chat.messages[0].status == .failed }
            try await Task.sleep(for: .milliseconds(1400))
            XCTAssertEqual(f.posts, ["first"], "A new wait or network failure stops the remainder")
            XCTAssertTrue(f.chat.messages.allSatisfy(\.awaitsManualRetry))
            XCTAssertTrue(f.chat.limitReleaseRetries.isEmpty)
            f.finish()
        }
    }

    func testExpiredHeldIntentResumesOnlyOnOpeningLoad() async throws {
        let f = try LimitReleaseFixture()
        defer { f.finish() }
        f.session.cooldowns.impose(.messages, seconds: 3600)
        f.held("expired")
        f.time.now.addTimeInterval(3601)
        f.chat.retryFailedAutomatically()
        await f.chat.load()
        XCTAssertEqual(f.posts, [], "Timer expiry and internal history reloads cannot resend")
        await f.chat.load(recheckLimits: true)
        try await f.waitUntil { f.posts == ["expired"] }
        XCTAssertFalse(StubURLProtocol.requests.contains { $0.query == "limits=1" }, "No quota check for expired waits")
    }

    func testBackgroundStopsTheRemainingReleasedMessages() async throws {
        let f = try LimitReleaseFixture()
        let gate = StubURLProtocol.Gate()
        defer { gate.release(); f.finish() }
        f.session.cooldowns.impose(.messages, seconds: 3600)
        f.held("first"); f.held("second")
        f.script.state.withLock {
            $0.sends = [.init(status: 201, body: "{\"conversation\":\(LimitReleaseFixture.Script.conversation),\"message\":\(LimitReleaseFixture.Script.message("first", seq: 1))}", gate: gate)]
        }
        await f.chat.load(recheckLimits: true)
        try await f.waitUntil { f.posts == ["first"] }
        f.chat.stopPolling()
        Reception.shared.applicationActive = false
        gate.release()
        try await f.waitUntil { f.chat.messages[0].status == .sent }
        XCTAssertEqual(f.posts, ["first"])
        XCTAssertTrue(f.chat.messages[1].awaitsManualRetry)
    }
}
