#if DEBUG && targetEnvironment(simulator)
import Foundation
import os

/// Simulated Reception replies for `CooldownFixture`, answering every Reception API request. Every request is appended to
/// `Caches/reception-fixture-requests.log`, so a maintainer can confirm that nothing is sent during a wait.
final class CooldownFixtureProtocol: URLProtocol {
    private struct Sent: Sendable { let seq: Int; let clientId: String; let text: String; let createdAt: String }
    private struct State: Sendable {
        var scenario: CooldownScenario?
        var counts: [String: Int] = [:]
        var sent: [Sent] = []
    }
    private static let state = OSAllocatedUnfairLock(initialState: State())
    private static let log = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
        .appendingPathComponent("reception-fixture-requests.log")

    static var scenario: CooldownScenario? {
        get { state.withLock { $0.scenario } }
        set { state.withLock { $0.scenario = newValue } }
    }

    static func resetLog() {
        guard let log else { return }
        try? Data().write(to: log)
    }

    override class func canInit(with request: URLRequest) -> Bool { request.url?.path.contains("/v1/") == true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let url = request.url else { return }
        let method = request.httpMethod ?? "GET"
        let path = url.path.components(separatedBy: "/v1/").last ?? url.path
        let route = url.query.map { path + "?" + $0 } ?? path
        let body = request.httpBody ?? request.httpBodyStream.map(Self.read) ?? Data()
        let (status, headers, text, finishes) = Self.reply(method: method, route: route, body: body)
        Self.record("\(method) /v1/\(route) -> \(status)")
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                             headerFields: headers.merging(["Content-Type": "application/json"]) { old, _ in old })
        else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(text.utf8))
        // An open live connection stays open until the SDK cancels it.
        if finishes { client?.urlProtocolDidFinishLoading(self) }
    }

    private static func reply(method: String, route: String, body: Data) -> (Int, [String: String], String, Bool) {
        let scenario = self.scenario
        let attempt = state.withLock { state -> Int in
            state.counts[method + route, default: 0] += 1
            return state.counts[method + route] ?? 1
        }
        switch (method, route) {
        case ("POST", "devices"):
            if scenario == .session && attempt == 1 { return limited("session", 480) }
            return (201, [:], #"{"token":"fixture-access","sessionSecret":"fixture-secret","verifiedUserId":null}"#, true)
        case ("POST", "devices/me/token"): return (200, [:], #"{"token":"fixture-access"}"#, true)
        case ("PATCH", "devices/me"): return (200, [:], #"{"verifiedUserId":null}"#, true)
        case ("POST", "uploads"):
            if scenario == .photo && attempt == 1 { return limited("uploads", 1800) }
            return (503, [:], #"{"error":{"code":"uploads_unavailable","message":"Fixture storage is not available."}}"#, true)
        case ("POST", "conversation/messages"): return message(scenario: scenario, attempt: attempt, body: body)
        case ("GET", "conversation/events"):
            if scenario == .stream { return limited("stream", 60) }
            return (200, ["Content-Type": "text/event-stream"], "retry: 2000\n\n", false)
        case ("GET", "conversation"):
            return (200, [:], #"{"boundedRead":true,"unreadPolling":[],"device":{"blocked":false,"verificationRequired":false},"conversation":\#(conversation()),"messages":\#(messages(after: 0))}"#, true)
        case ("POST", "conversation/read"):
            let through = (try? JSONSerialization.jsonObject(with: body) as? [String: Any])?["throughSeq"] as? Int ?? 0
            return (200, [:], #"{"conversationId":"fixture-conversation","readSeq":\#(through),"unreadCount":0}"#, true)
        case ("GET", "conversation/unread"):
            return (200, [:], #"{"hasConversation":true,"unreadCount":0,"status":"OPEN","lastMessageAt":null,"push":false,"unreadPolling":[]}"#, true)
        default:
            if route.hasPrefix("conversation/messages?after=") {
                let after = Int(route.components(separatedBy: "=").last ?? "") ?? 0
                return (200, [:], #"{"boundedRead":true,"device":{"blocked":false,"verificationRequired":false},"messages":\#(messages(after: after)),"hasMore":false,"conversation":{"id":"fixture-conversation","status":"OPEN"}}"#, true)
            }
            return (200, [:], "{}", true)
        }
    }

    private static func message(scenario: CooldownScenario?, attempt: Int, body: Data) -> (Int, [String: String], String, Bool) {
        switch scenario {
        case .messageShort where attempt == 1: return limited("messages", 45)
        case .messageLong where attempt == 1: return limited("messages", 7200)
        case .messageExpired where attempt == 1: return limited("messages", 65)
        case .requests where attempt == 1: return limited("requests", 50)
        case .blocked: return (403, [:], #"{"error":{"code":"blocked","message":"Blocked."}}"#, true)
        case .verification: return (403, [:], #"{"error":{"code":"verification_required","message":"Sign in."}}"#, true)
        default: break
        }
        let input = (try? JSONSerialization.jsonObject(with: body) as? [String: Any]) ?? [:]
        let clientId = input["clientId"] as? String ?? UUID().uuidString
        let text = input["text"] as? String ?? ""
        let sent = state.withLock { state -> Sent in
            if let known = state.sent.first(where: { $0.clientId == clientId }) { return known }
            let sent = Sent(seq: state.sent.count + 1, clientId: clientId, text: text,
                            createdAt: Date().formatted(.iso8601))
            state.sent.append(sent)
            return sent
        }
        return (201, [:], #"{"conversation":\#(conversation()),"message":\#(json(sent))}"#, true)
    }

    private static func limited(_ scope: String, _ seconds: Int) -> (Int, [String: String], String, Bool) {
        (429, ["Retry-After": String(seconds)], #"{"error":{"code":"rate_limited","message":"Please try again later.","retryScope":"\#(scope)"}}"#, true)
    }

    private static func conversation() -> String {
        guard let first = state.withLock({ $0.sent.first }) else { return "null" }
        return #"{"id":"fixture-conversation","status":"OPEN","unreadForUser":0,"createdAt":"\#(first.createdAt)"}"#
    }

    private static func messages(after: Int) -> String {
        "[" + state.withLock { $0.sent.filter { $0.seq > after } }.map(json).joined(separator: ",") + "]"
    }

    private static func json(_ sent: Sent) -> String {
        let text = (try? JSONSerialization.data(withJSONObject: [sent.text], options: [.fragmentsAllowed]))
            .flatMap { String(data: $0, encoding: .utf8) }.map { String($0.dropFirst().dropLast()) } ?? "\"\""
        return #"{"id":"fixture-\#(sent.seq)","clientId":"\#(sent.clientId)","seq":\#(sent.seq),"sender":"USER","kind":"TEXT","text":\#(text),"attachments":[],"actionClickedAt":null,"createdAt":"\#(sent.createdAt)"}"#
    }

    private static func record(_ line: String) {
        guard let log, let data = "\(Date().formatted(.iso8601)) \(line)\n".data(using: .utf8) else { return }
        state.withLock { _ in
            if let handle = try? FileHandle(forWritingTo: log) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: log)
            }
        }
    }

    private static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
#endif
