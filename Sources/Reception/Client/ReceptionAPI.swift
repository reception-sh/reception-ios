import Foundation

internal struct ReceptionAPI {
    /// The hosted Reception service. Only Reception's own test apps
    /// point it elsewhere, once, before configuring.
    nonisolated(unsafe) static var serviceURL = URL(string: "https://reception.sh")!

    let appId: String
    var baseURL = Self.serviceURL
    var chatRevision = 0
    weak var session: DeviceSession?

    /// `authenticated` requests carry the session's access token. A rejected token is replaced once and the request
    /// retried once; callers never hold tokens themselves. Known cooldowns are checked before the token and again
    /// right before sending, so a wait that started while this request was suspended still applies.
    func request<Response: Decodable>(_ path: String, method: String = "GET", authenticated: Bool = false,
                                      body: Data? = nil, expectedStatus: Int? = nil, photos: Bool = false) async throws -> Response {
        let scopes = RetryScope.gates(path, method: method, authenticated: authenticated, photos: photos)
        try await session?.admit(scopes)
        let token = authenticated ? try await activeSession().token() : nil
        let probe = try await session?.authorizeRequest(scopes) ?? false
        do {
            let value: Response
            do { value = try await send(path, method: method, token: token, body: body, expectedStatus: expectedStatus) }
            catch let error as ReceptionAPIError where token != nil && error.rejectsToken {
                let renewed = try await activeSession().renewedToken(replacing: token)
                try await session?.admit(scopes)
                value = try await send(path, method: method, token: renewed, body: body, expectedStatus: expectedStatus)
            }
            await session?.requestSucceeded(probe: probe)
            return value
        } catch let error as ReceptionAPIError {
            await session?.requestFailed(error, path: path, method: method)
            throw error
        }
    }

    /// One HTTP exchange without session bookkeeping.
    func send<Response: Decodable>(_ path: String, method: String, token: String?, body: Data?,
                                   expectedStatus: Int? = nil) async throws -> Response {
        var request = try urlRequest(path, token: token)
        request.httpMethod = method
        request.httpBody = body
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw ReceptionAPIError(code: "invalid_response", status: 0)
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom { decoder in
                let value = try decoder.singleValueContainer().decode(String.self)
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = formatter.date(from: value) { return date }
                formatter.formatOptions = [.withInternetDateTime]
                guard let date = formatter.date(from: value) else {
                    throw ReceptionAPIError(code: "invalid_date", status: http.statusCode)
                }
                return date
            }
            guard expectedStatus.map({ http.statusCode == $0 }) ?? (200..<300).contains(http.statusCode) else {
                Self.logRateLimit(http)
                let envelope = try? decoder.decode(ErrorEnvelope.self, from: data)
                let wait = Self.wait(http, named: envelope?.error.retryScope, path: path, method: method, authenticated: token != nil)
                throw ReceptionAPIError(code: envelope?.error.code ?? "http_error", status: http.statusCode,
                                      message: envelope?.error.message ?? "", resetRevision: envelope?.error.resetRevision,
                                      retryAfter: wait.seconds, retryScope: wait.scope)
            }
            do { return try decoder.decode(Response.self, from: data) }
            catch { throw ReceptionAPIError(code: "invalid_response", status: http.statusCode) }
        } catch let error as ReceptionAPIError { throw error }
        catch let error as URLError {
            throw ReceptionAPIError(code: Task.isCancelled ? "cancelled" : "connection_failed", status: 0,
                                    urlErrorCode: error.code.rawValue)
        } catch {
            throw ReceptionAPIError(code: Task.isCancelled ? "cancelled" : "connection_failed", status: 0)
        }
    }

    func deleteDevice(sessionSecret: String) async throws {
        struct Input: Encodable { let sessionSecret: String }
        let _: EmptyResponse = try await request("devices/me", method: "DELETE",
            body: Self.encode(Input(sessionSecret: sessionSecret)), expectedStatus: 200)
    }

    func stream(_ path: String) async throws -> URLSession.AsyncBytes {
        let scopes = RetryScope.gates(path, method: "GET", authenticated: true)
        try await session?.admit(scopes)
        let token = try await activeSession().token()
        let probe = try await session?.authorizeRequest(scopes) ?? false
        do {
            let bytes: URLSession.AsyncBytes
            do { bytes = try await openStream(path, token: token) }
            catch let error as ReceptionAPIError where error.rejectsToken {
                let renewed = try await activeSession().renewedToken(replacing: token)
                try await session?.admit(scopes)
                bytes = try await openStream(path, token: renewed)
            }
            await session?.requestSucceeded(probe: probe)
            return bytes
        } catch let error as ReceptionAPIError {
            await session?.requestFailed(error, path: path)
            throw error
        }
    }

    private func openStream(_ path: String, token: String) async throws -> URLSession.AsyncBytes {
        var request = try urlRequest(path, token: token)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 45
        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw ReceptionAPIError(code: "invalid_response", status: 0)
            }
            guard (200..<300).contains(http.statusCode) else {
                Self.logRateLimit(http)
                var data = Data()
                for try await byte in bytes { data.append(byte) }
                let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data)
                let wait = Self.wait(http, named: envelope?.error.retryScope, path: path, method: "GET", authenticated: true)
                throw ReceptionAPIError(code: envelope?.error.code ?? "http_error", status: http.statusCode,
                                      message: envelope?.error.message ?? "", resetRevision: envelope?.error.resetRevision,
                                      retryAfter: wait.seconds, retryScope: wait.scope)
            }
            return bytes
        } catch let error as ReceptionAPIError { throw error }
        catch let error as URLError {
            throw ReceptionAPIError(code: Task.isCancelled ? "cancelled" : "connection_failed", status: 0,
                                    urlErrorCode: error.code.rawValue)
        } catch {
            throw ReceptionAPIError(code: Task.isCancelled ? "cancelled" : "connection_failed", status: 0)
        }
    }

    private func activeSession() throws -> DeviceSession {
        guard let session else { throw ReceptionAPIError(code: "cancelled", status: 0) }
        return session
    }

    func urlRequest(_ path: String, token: String?) throws -> URLRequest {
        guard ["http", "https"].contains(baseURL.scheme?.lowercased() ?? ""),
              var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw ReceptionAPIError(code: "invalid_configuration", status: 0)
        }
        let parts = path.split(separator: "?", maxSplits: 1)
        guard let endpoint = parts.first else { throw ReceptionAPIError(code: "invalid_url", status: 0) }
        components.path = baseURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .split(separator: "/").map { "/" + $0 }.joined() + "/v1/" + String(endpoint)
        components.percentEncodedQuery = parts.count > 1 ? String(parts[1]) : nil
        guard let url = components.url else { throw ReceptionAPIError(code: "invalid_url", status: 0) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue(String(chatRevision), forHTTPHeaderField: "X-Reception-Revision")
        request.setValue(appId, forHTTPHeaderField: "X-App-Id")
        if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    static func accepts(appId: String) -> Bool {
        appId.range(of: "^app_[A-Za-z0-9]{22}$", options: .regularExpression) != nil
    }

    static func encode<Value: Encodable>(_ value: Value) throws -> Data {
        do { return try JSONEncoder().encode(value) }
        catch { throw ReceptionAPIError(code: "invalid_input", status: 0) }
    }

    static func logRateLimit(_ response: HTTPURLResponse) {
        guard response.statusCode == 429 else { return }
        let seconds = retryAfter(response) ?? 0
        Log.debug("Rate limited, HTTP 429, retry after \(seconds)s")
    }
}
