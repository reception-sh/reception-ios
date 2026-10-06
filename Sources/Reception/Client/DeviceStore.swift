import Foundation

@MainActor
internal final class DeviceStore {
    struct CredentialStorage {
        var read: (String) -> KeychainStore.ReadResult = { KeychainStore.read(account: $0) }
        var save: (String, String) -> Bool = { KeychainStore.save($0, account: $1) }
        var delete: (String) -> Bool = { KeychainStore.delete(account: $0) }
    }

    private let defaults = UserDefaults(suiteName: "com.reception.sdk")
    private let scope: String
    private let credentialStorage: CredentialStorage
    private var acceptsDrafts = true
    let chatCache: ChatCache
    let teamPhotoCache: TeamPhotoCache
    init(scope: String, credentialStorage: CredentialStorage = CredentialStorage()) {
        self.scope = scope
        self.credentialStorage = credentialStorage
        chatCache = ChatCache(scope: scope)
        teamPhotoCache = TeamPhotoCache(scope: scope)
    }

    var chatRevision: Int {
        get { defaults?.integer(forKey: key("chatRevision")) ?? 0 }
        set { defaults?.set(newValue, forKey: key("chatRevision")) }
    }

    func renewed() -> DeviceStore { DeviceStore(scope: scope, credentialStorage: credentialStorage) }

    func resetChat(revision: Int) {
        acceptsDrafts = false
        chatCache.clear()
        teamPhotoCache.clear()
        for name in ["cursor", "draftText", "hasConversation", "hasStartedChat",
                     "conversationStatus", "lastMessageAt", "pushActive", "unreadPolling", "pendingActionClicks"] { defaults?.removeObject(forKey: key(name)) }
        chatRevision = revision
    }

    var hasStartedChat: Bool {
        get { defaults?.bool(forKey: key("hasStartedChat")) == true || hasConversation }
        set { defaults?.set(newValue, forKey: key("hasStartedChat")) }
    }

    var hasConversation: Bool {
        get { defaults?.bool(forKey: key("hasConversation")) ?? false }
        set { defaults?.set(newValue, forKey: key("hasConversation")) }
    }

    var conversationStatus: String? {
        get { defaults?.string(forKey: key("conversationStatus")) }
        set { defaults?.set(newValue, forKey: key("conversationStatus")) }
    }

    var lastMessageAt: Date? {
        get { defaults?.object(forKey: key("lastMessageAt")) as? Date }
        set { defaults?.set(newValue, forKey: key("lastMessageAt")) }
    }

    var pushActive: Bool? {
        get { defaults?.object(forKey: key("pushActive")) as? Bool }
        set { defaults?.set(newValue, forKey: key("pushActive")) }
    }

    var unreadPolling: [UnreadStage]? {
        get {
            guard let data = defaults?.data(forKey: key("unreadPolling")) else { return nil }
            return try? JSONDecoder().decode([UnreadStage].self, from: data)
        }
        set {
            guard let newValue else { defaults?.removeObject(forKey: key("unreadPolling")); return }
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            defaults?.set(data, forKey: key("unreadPolling"))
        }
    }

    /// Server waits of this session; a new session namespace starts without them.
    var cooldowns: [ServerCooldowns.Cooldown] {
        get {
            guard let data = defaults?.data(forKey: key("cooldowns")) else { return [] }
            return (try? JSONDecoder().decode([ServerCooldowns.Cooldown].self, from: data)) ?? []
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            defaults?.set(data, forKey: key("cooldowns"))
        }
    }

    var lastLimitCheck: Date? {
        get { defaults?.object(forKey: key("lastLimitCheck")) as? Date }
        set { defaults?.set(newValue, forKey: key("lastLimitCheck")) }
    }

    var pendingActionClicks: [String] {
        get { defaults?.stringArray(forKey: key("pendingActionClicks")) ?? [] }
        set { if acceptsDrafts { defaults?.set(newValue, forKey: key("pendingActionClicks")) } }
    }

    var draftText: String {
        get { defaults?.string(forKey: key("draftText")) ?? "" }
        set { if acceptsDrafts { defaults?.set(newValue, forKey: key("draftText")) } }
    }
    private func key(_ name: String) -> String { scope + "." + name }

    /// Throws when secure storage cannot be read: an unreadable session is not a missing one.
    func loadCredentials() throws -> SessionCredentials? {
        switch credentialStorage.read(key("session")) {
        case .missing: return nil
        case .unavailable: throw ReceptionAPIError(code: "secure_storage_unavailable", status: 0)
        case .value(let value):
            guard let credentials = try? JSONDecoder().decode(SessionCredentials.self, from: Data(value.utf8)) else {
                throw ReceptionAPIError(code: "secure_storage_unavailable", status: 0)
            }
            return credentials
        }
    }
    var credentialsMissing: Bool { credentialStorage.read(key("session")) == .missing }
    func save(_ credentials: SessionCredentials) throws {
        guard let data = try? JSONEncoder().encode(credentials), let value = String(data: data, encoding: .utf8),
              credentialStorage.save(value, key("session")) else {
            throw ReceptionAPIError(code: "secure_storage_unavailable", status: 0)
        }
    }
    var cursor: Int64 {
        get { Int64(defaults?.string(forKey: key("cursor")) ?? "0") ?? 0 }
        set { defaults?.set(String(newValue), forKey: key("cursor")) }
    }
    var pending: DeviceIdentity {
        get {
            guard let data = defaults?.data(forKey: key("pending")),
                  let value = try? JSONDecoder().decode(DeviceIdentity.self, from: data) else { return DeviceIdentity() }
            return value
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            defaults?.set(data, forKey: key("pending"))
        }
    }
    func clear() {
        acceptsDrafts = false
        // A new namespace prevents reuse even when a locked Keychain refuses deletion.
        _ = credentialStorage.delete(key("session"))
        chatCache.clear()
        teamPhotoCache.clear()
        for name in ["chatRevision", "cursor", "pending", "draftText", "hasConversation", "hasStartedChat",
                     "conversationStatus", "lastMessageAt", "pushActive", "unreadPolling", "pendingActionClicks",
                     "cooldowns", "lastLimitCheck"] { defaults?.removeObject(forKey: key(name)) }
    }
    static func generation(for scope: String, rotate: Bool = false) -> String {
        let defaults = UserDefaults(suiteName: "com.reception.sdk")
        let key = scope + ".generation"
        if !rotate, let value = defaults?.string(forKey: key) { return value }
        let value = UUID().uuidString
        defaults?.set(value, forKey: key)
        return value
    }
}

internal struct DeviceIdentity: Codable {
    var externalUserId: String?
    var name: String?
    var email: String?
    var metadata: [String: String] = [:]
    var pushToken: String?
    var pushEnvironment: String?
}
