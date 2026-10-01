import XCTest
@testable import Reception

@MainActor
final class SubmissionRecoveryRaceTests: XCTestCase {
    func testStaleOpeningLoadRecoversThroughCoalescedHistoryReload() async throws {
        let f = try LimitReleaseFixture()
        let gate = StubURLProtocol.Gate()
        defer { gate.release(); f.finish() }
        await SubmissionRecoveryTests.failedSend(f, reply: .init(networkError: .notConnectedToInternet))
        f.chat.messages[0].status = .sending
        f.chat.saveMessages()
        let chat = SubmissionRecoveryTests.restart(f)
        defer { chat.stopPolling(); chat.session?.deactivate() }
        f.script.state.withLock { $0.conversation.gate = gate }
        let load = Task { await chat.load(recheckLimits: true) }
        try await f.waitUntil { StubURLProtocol.requests.contains { $0.path == "/v1/conversation" } }
        Reception.shared.invalidateRead()
        f.script.state.withLock { $0.conversation.gate = nil }
        gate.release()
        await load.value
        try await f.waitUntil { chat.messages.first?.status == .sent }
        XCTAssertEqual(f.posts.count, 2)
        XCTAssertEqual(StubURLProtocol.requests.filter { $0.path == "/v1/conversation" }.count, 2)
    }

    func testShortRequestCooldownRestoresWithoutSpendingItsBudget() async throws {
        let f = try LimitReleaseFixture()
        defer { f.finish() }
        await SubmissionRecoveryTests.failedSend(f, reply: .init(networkError: .notConnectedToInternet))
        let chat = SubmissionRecoveryTests.restart(f)
        defer { chat.stopPolling(); chat.session?.deactivate() }
        let id = chat.messages[0].id
        chat.session?.cooldowns.impose(.requests, seconds: 1)
        await chat.load(recheckLimits: true)
        XCTAssertEqual(f.posts.count, 1)
        XCTAssertEqual(chat.session?.retries[id]?.attempts, 0)
        try await f.waitUntil { chat.messages.first?.status == .sent }
        XCTAssertEqual(f.posts.count, 2)
    }

    func testClosingOrSwitchingSessionDuringOpeningCannotRecoverOldMessage() async throws {
        for switchSession in [false, true] {
            let f = try LimitReleaseFixture()
            let gate = StubURLProtocol.Gate()
            await SubmissionRecoveryTests.failedSend(f, reply: .init(networkError: .notConnectedToInternet))
            let chat = SubmissionRecoveryTests.restart(f)
            f.script.state.withLock { $0.conversation.gate = gate }
            let load = Task { await chat.load(recheckLimits: true) }
            try await f.waitUntil { StubURLProtocol.requests.contains { $0.path == "/v1/conversation" } }
            chat.stopPolling(); chat.isVisible = false
            if switchSession { chat.session?.deactivate(); Reception.shared.session = nil }
            gate.release()
            await load.value
            XCTAssertEqual(f.posts.count, 1)
            chat.session?.deactivate(); f.finish()
        }
    }

    func testCachedPhotoIDsSurviveAndIncompletePhotoSetsNeverPost() async throws {
        for incomplete in [false, true] {
            let f = try LimitReleaseFixture()
            f.held("photo", photos: true, eligible: false)
            f.chat.messages[0].awaitsManualRetry = false
            f.chat.messages[0].retryAfterTransientFailure = true
            f.chat.messages[0].expectedImageCount = incomplete ? 2 : 1
            f.chat.saveMessages()
            let chat = SubmissionRecoveryTests.restart(f)
            await chat.load(recheckLimits: true)
            try await f.waitUntil { chat.messages.first?.status == .sent || chat.session?.retries["photo"]?.stopped == true }
            if incomplete {
                XCTAssertEqual(f.posts, [])
                XCTAssertEqual(chat.messages.first?.status, .failed)
                XCTAssertFalse(chat.messages[0].retryAfterTransientFailure)
            } else {
                XCTAssertEqual(f.posts, ["photo"])
                let request = try XCTUnwrap(StubURLProtocol.requests.first { $0.path == "/v1/conversation/messages" })
                let body = try XCTUnwrap(request.body)
                let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
                XCTAssertEqual(json["attachmentIds"] as? [String], ["uploaded-photo"])
                XCTAssertFalse(StubURLProtocol.requests.contains { $0.path == "/v1/uploads" })
            }
            chat.stopPolling(); chat.session?.deactivate(); f.finish()
        }
    }

    func testPartialPhotoUploadResumesRemainingPhotoAndRetainsCompletedID() async throws {
        let f = try LimitReleaseFixture()
        defer { f.finish() }
        let photo = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { _ in }
        f.chat.messages.append(Message(id: "partial-photo", sender: "USER", text: "photos", attachments: [],
            createdAt: Date(), status: .failed, retryAfterTransientFailure: true,
            images: [photo, photo], attachmentIds: ["uploaded-photo"]))
        f.chat.saveMessages()
        let chat = SubmissionRecoveryTests.restart(f)
        defer { chat.stopPolling(); chat.session?.deactivate() }
        StubURLProtocol.install { [script = f.script] request in
            if request.path == "/v1/uploads" {
                return .init(body: #"{"attachmentId":"remaining-photo","uploadUrl":"https://reception.test/storage","headers":{}}"#)
            }
            return script.reply(request)
        }
        await chat.load(recheckLimits: true)
        try await f.waitUntil { chat.messages.first?.status == .sent }
        XCTAssertEqual(f.posts, ["partial-photo"])
        XCTAssertEqual(StubURLProtocol.requests.filter { $0.path == "/v1/uploads" }.count, 1)
        XCTAssertEqual(StubURLProtocol.requests.filter { $0.path == "/storage" }.count, 1)
        let request = try XCTUnwrap(StubURLProtocol.requests.first { $0.path == "/v1/conversation/messages" })
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.body)) as? [String: Any])
        XCTAssertEqual(json["attachmentIds"] as? [String], ["uploaded-photo", "remaining-photo"])
    }

}
