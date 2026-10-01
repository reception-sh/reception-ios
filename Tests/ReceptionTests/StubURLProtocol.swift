import Foundation
import os

/// Answers requests to https://reception.test with canned replies and records them.
final class StubURLProtocol: URLProtocol {
    struct Request: Sendable {
        let method: String
        let path: String
        let query: String?
        let authorization: String?
        let body: Data?
    }
    struct Reply: Sendable {
        var status = 200
        var body = "{}"
        var headers: [String: String] = [:]
        var delay: TimeInterval = 0
        var gate: Gate?
        var networkError: URLError.Code?
    }
    final class Gate: Sendable {
        private struct State { var open = false; var deliveries: [() -> Void] = [] }
        private let state = OSAllocatedUnfairLock(initialState: State())

        func release() {
            let deliveries = state.withLock { state in
                state.open = true
                defer { state.deliveries.removeAll() }
                return state.deliveries
            }
            for deliver in deliveries { deliver() }
        }

        func wait(_ deliver: @escaping () -> Void) {
            let open = state.withLock { state in
                if !state.open { state.deliveries.append(deliver) }
                return state.open
            }
            if open { deliver() }
        }
    }
    typealias Responder = @Sendable (Request) -> Reply

    private struct State {
        var requests: [Request] = []
        var responder: Responder?
    }
    private static let state = OSAllocatedUnfairLock(initialState: State())
    private let stopped = OSAllocatedUnfairLock(initialState: false)

    static func install(_ responder: @escaping Responder) {
        state.withLock { $0 = State(requests: [], responder: responder) }
        URLProtocol.unregisterClass(StubURLProtocol.self)
        URLProtocol.registerClass(StubURLProtocol.self)
    }

    static func uninstall() {
        URLProtocol.unregisterClass(StubURLProtocol.self)
        state.withLock { $0 = State() }
    }

    static var requests: [Request] { state.withLock { $0.requests } }

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "reception.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let recorded = Request(method: request.httpMethod ?? "GET", path: request.url?.path ?? "",
                               query: request.url?.query,
                               authorization: request.value(forHTTPHeaderField: "Authorization"),
                               body: request.httpBody ?? Self.read(request.httpBodyStream))
        let responder = Self.state.withLock { state -> Responder? in
            state.requests.append(recorded)
            return state.responder
        }
        let reply = responder?(recorded) ?? Reply(status: 500)
        if let error = reply.networkError {
            client?.urlProtocol(self, didFailWithError: URLError(error))
            return
        }
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1",
                                             headerFields: reply.headers.merging(["Content-Type": "application/json"]) { old, _ in old })
        else { return }
        let deliver = { [client] in
            guard !self.stopped.withLock({ $0 }) else { return }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
        if let gate = reply.gate {
            gate.wait(deliver)
        } else if reply.delay > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + reply.delay, execute: deliver)
        } else {
            deliver()
        }
    }

    override func stopLoading() { stopped.withLock { $0 = true } }

    private static func read(_ stream: InputStream?) -> Data? {
        guard let stream else { return nil }
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
