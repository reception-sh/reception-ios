import XCTest
import os
@testable import Reception

/// The poll or load that follows another GET belongs to the chat's activation: closing the chat ends its request, and
/// a chat reopened while a cancelled request is still unwinding loads once that request has ended.
@MainActor
final class FollowUpPollTests: XCTestCase {
    func testAFollowUpPollEndsWithTheChatAndDoesNotBlockReopening() async throws {
        let f = try LimitReleaseFixture()
        Reception.shared.updatesAppBadge = false
        let loadGate = StubURLProtocol.Gate()
        let pollGate = StubURLProtocol.Gate()
        defer { loadGate.release(); pollGate.release(); f.finish(); Reception.shared.updatesAppBadge = true }
        f.session.store.hasConversation = true
        StubURLProtocol.install { [script = f.script] request in
            switch (request.method, request.path) {
            case ("GET", "/v1/conversation"):
                return .init(body: #"{"conversation":\#(LimitReleaseFixture.Script.conversation),"messages":[],"boundedRead":true}"#, gate: loadGate)
            case ("GET", "/v1/conversation/events"):
                return .init(body: "retry: 2000\n\n", holdOpen: true)
            case ("GET", "/v1/conversation/messages"):
                return .init(body: #"{"conversation":\#(LimitReleaseFixture.Script.conversation),"messages":[],"boundedRead":true}"#, gate: pollGate)
            case ("POST", "/v1/conversation/read"):
                return .init(body: #"{"conversationId":"c1","readSeq":0,"unreadCount":0}"#)
            default: return script.reply(request)
            }
        }
        // A reload outside the stream owns the GET; the stream's opening poll queues behind it.
        let load = Task { await f.chat.load() }
        try await f.waitUntil { StubURLProtocol.requests.contains { $0.path == "/v1/conversation" } }
        f.chat.startPolling()
        try await f.waitUntil { f.chat.streamConnected }
        loadGate.release()
        await load.value
        try await f.waitUntil { StubURLProtocol.requests.contains { $0.path == "/v1/conversation/messages" } }
        f.chat.stopPolling()
        f.chat.isVisible = false
        // A cancelled URLSession request completes independently of this closed response gate.
        for _ in 0..<20 where f.chat.loading { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(f.chat.loading, "stopPolling must cancel the deferred fetch holding the shared loading lock")
        let getsBefore = StubURLProtocol.requests.filter { $0.path == "/v1/conversation" }.count
        f.chat.isVisible = true
        await f.chat.load(recheckLimits: true)
        XCTAssertGreaterThan(StubURLProtocol.requests.filter { $0.path == "/v1/conversation" }.count, getsBefore,
                             "Reopening must be able to reload history while the old poll's response is held")
        pollGate.release()
        try await f.waitUntil { !f.chat.loading }
    }

    private func requests(_ path: String) -> [StubURLProtocol.Request] {
        StubURLProtocol.requests.filter { $0.method == "GET" && $0.path == path }
    }

    func testAnImmediateReopenKeepsItsLoadAndLimitsRecheck() async throws {
        let f = try LimitReleaseFixture()
        Reception.shared.updatesAppBadge = false
        let loadGate = StubURLProtocol.Gate(), pollGate = StubURLProtocol.Gate()
        defer { loadGate.release(); pollGate.release(); f.finish(); Reception.shared.updatesAppBadge = true }
        f.session.store.hasConversation = true
        StubURLProtocol.install { [script = f.script] r in
            switch (r.method, r.path) {
            case ("GET", "/v1/conversation"):
                return .init(body: #"{"conversation":\#(LimitReleaseFixture.Script.conversation),"messages":[],"boundedRead":true,"limits":{"messages":0}}"#, gate: loadGate)
            case ("GET", "/v1/conversation/events"): return .init(body: "retry: 2000\n\n", holdOpen: true)
            case ("GET", "/v1/conversation/messages"):
                return .init(body: #"{"conversation":\#(LimitReleaseFixture.Script.conversation),"messages":[],"boundedRead":true}"#, gate: pollGate)
            case ("POST", "/v1/conversation/read"): return .init(body: #"{"conversationId":"c1","readSeq":0,"unreadCount":0}"#)
            default: return script.reply(r)
            }
        }
        let load = Task { await f.chat.load() }
        try await f.waitUntil { self.requests("/v1/conversation").count == 1 }
        f.chat.startPolling()
        try await f.waitUntil { f.chat.streamConnected }
        loadGate.release(); await load.value
        try await f.waitUntil { self.requests("/v1/conversation/messages").count == 1 }
        f.session.cooldowns.impose(.messages, seconds: 3600)
        let old = f.chat.followUp
        f.chat.stopPolling()
        // Same-actor immediate foreground/reopen: no artificial wait for cancellation completion.
        await f.chat.load(recheckLimits: true)
        f.chat.startPolling()
        await old?.value
        pollGate.release()
        // The reopening load waited for the cancelled poll to end.
        try await f.waitUntil { self.requests("/v1/conversation").count > 1 && !f.chat.loading }
        XCTAssertTrue(requests("/v1/conversation").contains { $0.query == "limits=1" }, "Reopen lost its limits recheck")
        XCTAssertNil(f.session.retries["poll"], "Cancellation is not a poll failure")
    }

    func testAFollowUpOfAFollowUpEndsWithTheChatToo() async throws {
        let f = try LimitReleaseFixture()
        let first = StubURLProtocol.Gate(), second = StubURLProtocol.Gate(), third = StubURLProtocol.Gate()
        defer { first.release(); second.release(); third.release(); f.finish() }
        f.session.store.hasConversation = true
        let count = OSAllocatedUnfairLock(initialState: 0)
        StubURLProtocol.install { [script = f.script] r in
            if r.path == "/v1/conversation/events" { return .init(gate: StubURLProtocol.Gate()) }
            if r.method == "GET", r.path == "/v1/conversation/messages" {
                let n = count.withLock { $0 += 1; return $0 }
                return .init(body: #"{"conversation":null,"messages":[]}"#, gate: n == 1 ? first : (n == 2 ? second : third))
            }
            return script.reply(r)
        }
        f.chat.startPolling()
        let root = Task { await f.chat.poll() }
        try await f.waitUntil { self.requests("/v1/conversation/messages").count == 1 }
        await f.chat.poll()
        first.release(); await root.value
        try await f.waitUntil { self.requests("/v1/conversation/messages").count == 2 }
        await f.chat.poll()
        second.release()
        try await f.waitUntil { self.requests("/v1/conversation/messages").count == 3 }
        let last = f.chat.followUp
        f.chat.stopPolling()
        await last?.value
        XCTAssertFalse(f.chat.loading)
        XCTAssertNil(f.session.retries["poll"])
        XCTAssertNil(f.chat.followUp)
    }

    func testADiscardedLoadKeepsItsLimitsRecheckSpent() async throws {
        let f = try LimitReleaseFixture()
        Reception.shared.updatesAppBadge = false
        let gate = StubURLProtocol.Gate()
        defer { gate.release(); f.finish(); Reception.shared.updatesAppBadge = true }
        let count = OSAllocatedUnfairLock(initialState: 0)
        f.session.cooldowns.impose(.messages, seconds: 3600)
        StubURLProtocol.install { [script = f.script] r in
            if r.method == "GET", r.path == "/v1/conversation" {
                let n = count.withLock { $0 += 1; return $0 }
                return .init(body: n == 1
                    ? #"{"conversation":null,"messages":[],"limits":{"messages":0}}"#
                    : #"{"conversation":\#(LimitReleaseFixture.Script.conversation),"messages":[],"boundedRead":true,"limits":{"messages":0}}"#,
                             gate: n == 1 ? gate : nil)
            }
            if r.path == "/v1/conversation/read" { return .init(body: #"{"conversationId":"c1","readSeq":0,"unreadCount":0}"#) }
            return script.reply(r)
        }
        let load = Task { await f.chat.load(recheckLimits: true) }
        try await f.waitUntil { self.requests("/v1/conversation").count == 1 }
        // Same state transition as receipt of a first-conversation push; hold unread/stream out of this isolated probe.
        f.session.store.hasConversation = true
        gate.release(); await load.value
        try await f.waitUntil { self.requests("/v1/conversation").count == 2 && !f.chat.loading }
        XCTAssertNotNil(f.session.cooldowns.blocking([.messages]), "Discarded answer must not release a hold")
        XCTAssertEqual(requests("/v1/conversation").map { $0.query ?? "none" }, ["limits=1", "none"])
    }

    func testAReopenLoadsOnceAFollowUpPollWaitingForATokenEnds() async throws {
        let f = try LimitReleaseFixture()
        Reception.shared.updatesAppBadge = false
        let loadGate = StubURLProtocol.Gate(), tokenGate = StubURLProtocol.Gate()
        defer { loadGate.release(); tokenGate.release(); f.finish(); Reception.shared.updatesAppBadge = true }
        f.session.store.hasConversation = true
        StubURLProtocol.install { [script = f.script] r in
            switch (r.method, r.path) {
            case ("GET", "/v1/conversation"):
                return .init(body: #"{"conversation":\#(LimitReleaseFixture.Script.conversation),"messages":[],"boundedRead":true}"#, gate: loadGate)
            case ("GET", "/v1/conversation/events"): return .init(body: "retry: 2000\n\n", holdOpen: true)
            case ("GET", "/v1/conversation/messages"):
                return .init(status: 401, body: #"{"error":{"code":"unauthorized","message":"Expired"}}"#)
            case ("POST", "/v1/devices/me/token"): return .init(body: #"{"token":"new-token"}"#, gate: tokenGate)
            case ("POST", "/v1/conversation/read"): return .init(body: #"{"conversationId":"c1","readSeq":0,"unreadCount":0}"#)
            default: return script.reply(r)
            }
        }
        let load = Task { await f.chat.load() }
        try await f.waitUntil { self.requests("/v1/conversation").count == 1 }
        f.chat.startPolling()
        try await f.waitUntil { f.chat.streamConnected }
        loadGate.release(); await load.value
        try await f.waitUntil { StubURLProtocol.requests.contains { $0.path == "/v1/devices/me/token" } }
        let poll = try XCTUnwrap(f.chat.followUp)
        f.chat.stopPolling()
        // The cancelled poll cannot leave before the shared renewal answers; the reopening load waits for it.
        await f.chat.load(recheckLimits: true)
        XCTAssertEqual(requests("/v1/conversation").count, 1)
        tokenGate.release()
        await poll.value
        try await f.waitUntil { self.requests("/v1/conversation").count > 1 && !f.chat.loading }
        XCTAssertNil(f.session.retries["poll"], "Cancellation must not spend the poll retry budget")
    }

    func testACancelledOpeningLeavesNoLoadBehind() async throws {
        let f = try LimitReleaseFixture()
        Reception.shared.updatesAppBadge = false
        let patch = StubURLProtocol.Gate()
        defer { patch.release(); f.finish(); Reception.shared.updatesAppBadge = true }
        StubURLProtocol.install { [script = f.script] r in
            if r.method == "PATCH", r.path == "/v1/devices/me" { return .init(body: #"{"verifiedUserId":null}"#, gate: patch) }
            return script.reply(r)
        }
        // An opening awaits session.update, which is shared and does not complete just because its waiter cancels.
        let old = Task { await f.chat.load() }
        try await f.waitUntil { StubURLProtocol.requests.contains { $0.method == "PATCH" } }
        // A replacement .task(id:) has been enqueued, but the chat closes before its actor job starts.
        let opening = Task { await f.chat.load(recheckLimits: true) }
        opening.cancel(); old.cancel()
        f.chat.stopPolling(); f.chat.isVisible = false
        await opening.value
        patch.release(); await old.value
        // Joining update owners is insufficient: wait for the follow-up that was wrongly created.
        await f.chat.followUp?.value
        XCTAssertFalse(f.chat.isChatActive)
        XCTAssertEqual(StubURLProtocol.requests.filter { $0.method == "GET" && $0.path == "/v1/conversation" }.count, 0,
                       "Cancelled opening queued a fresh uncancelled full GET after stopPolling cleared activation work")
    }

    // A real reload task loses its handle once its GET starts; foreground queues a recheck behind it.
    func testAScheduledReloadTakesTheWaitingLoadsLimitsRecheck() async throws {
        let f = try LimitReleaseFixture()
        Reception.shared.updatesAppBadge = false
        let gate = StubURLProtocol.Gate()
        defer { gate.release(); f.finish(); Reception.shared.updatesAppBadge = true }
        f.session.store.hasConversation = true
        f.session.cooldowns.impose(.messages, seconds: 3600)
        let count = OSAllocatedUnfairLock(initialState: 0)
        StubURLProtocol.install { [script = f.script] r in
            if r.method == "GET", r.path == "/v1/conversation" {
                let n = count.withLock { $0 += 1; return $0 }
                return .init(body: #"{"conversation":\#(LimitReleaseFixture.Script.conversation),"messages":[],"boundedRead":true,"limits":{"messages":0}}"#, gate: n == 1 ? gate : nil)
            }
            if r.path == "/v1/conversation/read" { return .init(body: #"{"conversationId":"c1","readSeq":0,"unreadCount":0}"#) }
            return script.reply(r)
        }
        f.chat.reloadAfterStaleGet()
        try await f.waitUntil { self.requests("/v1/conversation").count == 1 }
        XCTAssertNil(f.chat.reloadTask, "The in-flight reload has relinquished its cancellation handle")
        f.chat.stopPolling() // background invalidates its read generation but cannot cancel the reload
        await f.chat.load(recheckLimits: true) // foreground queues behind the older reload
        gate.release()
        try await f.waitUntil { self.requests("/v1/conversation").count == 2 && !f.chat.loading }
        XCTAssertEqual(requests("/v1/conversation").map { $0.query ?? "none" }, ["none", "limits=1"], "Queued opening recheck was discarded in favor of a plain stale reload")
        XCTAssertNil(f.session.cooldowns.blocking([.messages]), "The server released this hold but the queued recheck was lost")
    }

    func testARefusedLoadLeavesTheWaitingPollToRun() async throws {
        let f = try LimitReleaseFixture()
        Reception.shared.updatesAppBadge = false
        let gate = StubURLProtocol.Gate(), streamGate = StubURLProtocol.Gate()
        defer { gate.release(); streamGate.release(); f.finish(); Reception.shared.updatesAppBadge = true }
        f.session.store.hasConversation = true
        StubURLProtocol.install { [script = f.script] r in
            if r.method == "GET", r.path == "/v1/conversation" { return .init(status: 500, gate: gate) }
            if r.path == "/v1/conversation/events" { return .init(gate: streamGate) }
            if r.method == "GET", r.path == "/v1/conversation/messages" {
                return .init(body: #"{"conversation":\#(LimitReleaseFixture.Script.conversation),"messages":[],"boundedRead":true}"#)
            }
            if r.path == "/v1/conversation/read" { return .init(body: #"{"conversationId":"c1","readSeq":0,"unreadCount":0}"#) }
            return script.reply(r)
        }
        f.chat.startPolling()
        let owner = Task { await f.chat.load() }
        try await f.waitUntil { self.requests("/v1/conversation").count == 1 }
        // Model the prior seven failed openings, after this GET starts so the test need not sleep through backoff.
        for _ in 0..<7 { f.session.retries["load", default: RetryState()].failed(URLError(.networkConnectionLost)) }
        await f.chat.load()
        await f.chat.poll() // changed while GET is held
        gate.release(); await owner.value
        try await f.waitUntil { self.requests("/v1/conversation/messages").count == 1 }
        XCTAssertTrue(f.session.retries["load"]?.stopped == true)
        XCTAssertEqual(requests("/v1/conversation/messages").count, 1, "A load refused by its budget is not a replacement for the queued poll")
    }

    func testACancelledLoadLeavesNothingBehindInAVisibleChatAndTheNextOneRuns() async throws {
        let f = try LimitReleaseFixture()
        Reception.shared.updatesAppBadge = false
        let patch = StubURLProtocol.Gate()
        defer { patch.release(); f.finish(); Reception.shared.updatesAppBadge = true }
        f.session.store.hasConversation = true
        f.session.cooldowns.impose(.messages, seconds: 3600)
        StubURLProtocol.install { [script = f.script] r in
            if r.method == "PATCH" { return .init(body: #"{"verifiedUserId":null}"#, gate: patch) }
            if r.path == "/v1/conversation" { return .init(body: #"{"conversation":\#(LimitReleaseFixture.Script.conversation),"messages":[{"id":"m1","seq":1,"sender":"AGENT","text":"Hi","attachments":[],"createdAt":"2026-09-25T10:00:00.000Z"}],"boundedRead":true,"limits":{"messages":0}}"#) }
            if r.path == "/v1/conversation/read" { return .init(body: #"{"conversationId":"c1","readSeq":1,"unreadCount":0}"#) }
            return script.reply(r)
        }
        let old = Task { await f.chat.load() }
        try await f.waitUntil { StubURLProtocol.requests.contains { $0.method == "PATCH" } }
        old.cancel()
        let cancelled = Task { await f.chat.load(recheckLimits: true) }
        cancelled.cancel()
        await cancelled.value
        XCTAssertNil(f.chat.loadAfterFetch, "Visibility must not mask the cancellation guard")
        await f.chat.load(recheckLimits: true)
        XCTAssertEqual(f.chat.loadAfterFetch, true)
        patch.release(); await old.value
        await f.chat.followUp?.value
        XCTAssertEqual(requests("/v1/conversation").map { $0.query ?? "none" }, ["limits=1"])
        XCTAssertNil(f.chat.loadAfterFetch)
        XCTAssertEqual(f.chat.messages.map(\.id), ["m1"])
    }
}
