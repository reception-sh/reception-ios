import Foundation

internal struct ReceptionAPIError: Error {
    let code: String
    let status: Int
    var message: String = ""
    var resetRevision: Int?
    var urlErrorCode: Int?
    var retryAfter: Int?
    /// Set when the service asked this device to wait before repeating work of that scope.
    var retryScope: RetryScope?

    /// A known cooldown kept this request off the network, so it cost no attempt.
    var isCooldown: Bool { code == "cooldown" }

    /// The only response that replaces an access token; `session_revoked` comes from the refresh itself.
    var rejectsToken: Bool { status == 401 && code == "unauthorized" }

    /// Identity token failures from a registration or device update; they never end the session itself.
    var rejectsIdentityToken: Bool {
        ["identity_token_invalid", "identity_token_expired", "identity_not_configured", "identity_mismatch"].contains(code)
    }

    static func isTransient(_ error: Error) -> Bool {
        if let error = error as? URLError { return error.code != .cancelled }
        guard let error = error as? ReceptionAPIError, error.code != "cancelled" else { return false }
        return (error.urlErrorCode != nil && error.urlErrorCode != URLError.cancelled.rawValue) || (500..<600).contains(error.status)
            || error.status == 408 || error.status == 429
    }
}

extension ReceptionAPI {
    /// The service never asks for more than a day; a longer value is capped rather than trusted.
    static let maximumRetryAfter = 86_400

    /// Whole seconds from a `429` response's `Retry-After`. HTTP dates and negative values count as missing.
    static func retryAfter(_ response: HTTPURLResponse, maximum: Int = maximumRetryAfter) -> Int? {
        response.statusCode == 429 ? headerSeconds(response, maximum: maximum) : nil
    }

    /// A `429` waits for the scope the service names, else its route's limit or the request budget. A `503` waits only
    /// when the service names a scope; every other `503` remains an ordinary transient failure with backoff.
    static func wait(_ response: HTTPURLResponse, named: String?, path: String, method: String,
                     authenticated: Bool) -> (seconds: Int?, scope: RetryScope?) {
        let scope = named.flatMap(RetryScope.init(rawValue:))
        switch response.statusCode {
        case 429:
            let seconds = retryAfter(response)
            guard seconds != nil, !RetryScope.exempt(path, method: method) else { return (seconds, nil) }
            return (seconds, scope ?? RetryScope.route(path, method: method) ?? (authenticated ? .requests : nil))
        case 503:
            guard let scope, let seconds = headerSeconds(response, maximum: maximumRetryAfter),
                  !RetryScope.exempt(path, method: method) else { return (nil, nil) }
            return (seconds, scope)
        default:
            return (nil, nil)
        }
    }

    /// At least one second, so a `0` never turns into back-to-back retries.
    private static func headerSeconds(_ response: HTTPURLResponse, maximum: Int) -> Int? {
        guard let raw = response.value(forHTTPHeaderField: "Retry-After"),
              let seconds = Int(raw.trimmingCharacters(in: .whitespaces)), seconds >= 0 else { return nil }
        return min(max(seconds, 1), maximum)
    }

    struct ErrorEnvelope: Decodable {
        struct Detail: Decodable {
            let code: String
            let message: String
            let resetRevision: Int?
            let retryScope: String?

            private enum CodingKeys: String, CodingKey { case code, message, resetRevision, retryScope }

            init(from decoder: Decoder) throws {
                let values = try decoder.container(keyedBy: CodingKeys.self)
                code = try values.decode(String.self, forKey: .code)
                message = try values.decode(String.self, forKey: .message)
                resetRevision = try values.decodeIfPresent(Int.self, forKey: .resetRevision)
                // A malformed scope from a newer service must not hide the error code.
                retryScope = try? values.decodeIfPresent(String.self, forKey: .retryScope)
            }
        }
        let error: Detail
    }
}
