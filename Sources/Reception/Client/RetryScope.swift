import Foundation

/// The limit behind a server wait, from the optional `error.retryScope` of a rejection.
internal enum RetryScope: String, Codable, CaseIterable, Sendable {
    case messages, uploads, requests, session, stream

    /// The limit a route consumes. A `429` from an older service without a scope waits for it.
    static func route(_ path: String, method: String) -> RetryScope? {
        switch (method, endpoint(path)) {
        case ("POST", "conversation/messages"): .messages
        case ("POST", "uploads"): .uploads
        case ("GET", "conversation/events"): .stream
        case ("POST", "devices"), ("POST", "devices/me/token"): .session
        default: nil
        }
    }

    /// The cooldowns that must be over before a request may reach the network: its route's own limit,
    /// uploads for a message with photos, and the per-device request budget for bearer requests.
    static func gates(_ path: String, method: String, authenticated: Bool, photos: Bool = false) -> [RetryScope] {
        guard !exempt(path, method: method) else { return [] }
        var scopes = route(path, method: method).map { [$0] } ?? []
        if photos { scopes.append(.uploads) }
        if authenticated { scopes.append(.requests) }
        return scopes
    }

    /// Account deletion and session revocation stay possible during every cooldown and never start one.
    static func exempt(_ path: String, method: String) -> Bool {
        (method == "DELETE" && endpoint(path) == "devices/me") || (method == "POST" && endpoint(path) == "devices/me/logout")
    }

    private static func endpoint(_ path: String) -> String { String(path.prefix { $0 != "?" }) }
}
