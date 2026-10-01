import Foundation
import CryptoKit

internal struct AppearanceCache {
    private let key: String
    private let defaults = UserDefaults(suiteName: "com.reception.sdk.appearance")
    static let maximumBytes = 65_536

    init(scope: String) {
        key = SHA256.hash(data: Data(scope.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func load() -> AppearanceEnvelope? {
        guard let data = defaults?.data(forKey: key), data.count <= Self.maximumBytes,
              let value = try? JSONDecoder().decode(AppearanceEnvelope.self, from: data),
              value.schemaVersion == 1, value.revision >= 0 else { return nil }
        return value
    }

    func save(_ value: AppearanceEnvelope) {
        guard let data = try? JSONEncoder().encode(value), data.count <= Self.maximumBytes else { return }
        defaults?.set(data, forKey: key)
    }
}
