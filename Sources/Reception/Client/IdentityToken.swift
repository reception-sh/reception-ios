import Foundation

/// A token from `identify(token:)`, kept in memory only. `userId` is read without verifying the signature;
/// the service verifies the token and applies the same `user_id` rules, so both sides compare the same string.
internal struct IdentityToken: Equatable {
    let value: String
    let userId: String
    /// Accepted by a registration or device update. Registrations always carry the token; updates only until then.
    var sent = false

    init?(_ value: String) {
        guard let userId = Self.userId(in: value) else { return nil }
        self.value = value
        self.userId = userId
    }

    func matchesUser(verifiedUserId: String?, unverifiedUserId: String?, stagedUserId: String? = nil) -> Bool {
        if let verifiedUserId { return UserIdentity.matches(userId, verifiedUserId) }
        return (unverifiedUserId == nil || UserIdentity.matches(unverifiedUserId, userId))
            && (stagedUserId == nil || UserIdentity.matches(stagedUserId, userId))
    }

    static func userId(in token: String) -> String? {
        guard token.utf16.count <= 4096 else { return nil }
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, let payload = decode(parts[1]),
              let claims = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else { return nil }
        return userId(claim: claims["user_id"])
    }

    /// Strings are used as they are; a JSON integer within ±(2^53 − 1) becomes its decimal string.
    static func userId(claim: Any?) -> String? {
        if let value = claim as? String {
            return (1...255).contains(value.utf16.count) ? value : nil
        }
        guard let number = claim as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let value = number.doubleValue
        guard value.isFinite, value.rounded() == value, abs(value) <= 9_007_199_254_740_991 else { return nil }
        return String(Int64(value))
    }

    private static func decode(_ segment: Substring) -> Data? {
        var base64 = segment.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64)
    }
}
