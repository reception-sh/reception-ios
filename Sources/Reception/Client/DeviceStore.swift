import Foundation
import Observation

/// Observable only for the values the chat shows directly; everything else is read on demand.
@MainActor
internal final class DeviceStore: Observable {
    struct CredentialStorage {
        var read: (String) -> KeychainStore.ReadResult = { KeychainStore.read(account: $0) }
        var save: (String, String) -> Bool = { KeychainStore.save($0, account: $1) }
        var delete: (String) -> Bool = { KeychainStore.delete(account: $0) }
    }

    private let defaults = UserDefaults(suiteName: "com.reception.sdk")
    private let scope: String
    /// Values about this device rather than its session, kept across logout.
    private let deviceScope: String
    private let registrar = ObservationRegistrar()
    private let credentialStorage: CredentialStorage
    private var acceptsDrafts = true
    let chatCache: ChatCache
    let teamProfileCache: TeamProfileCache
    init(scope: String, deviceScope: String? = nil, credentialStorage: CredentialStorage = CredentialStorage()) {
        self.scope = scope
        self.deviceScope = deviceScope ?? scope
        self.credentialStorage = credentialStorage
        chatCache = ChatCache(scope: scope)
        teamProfileCache = TeamProfileCache(scope: scope)
    }

    var chatRevision: Int {
        get { defaults?.integer(forKey: key("chatRevision")) ?? 0 }
        set { defaults?.set(newValue, forKey: key("chatRevision")) }
    }

    func renewed() -> DeviceStore { DeviceStore(scope: scope, deviceScope: deviceScope, credentialStorage: credentialStorage) }

    func resetChat(revision: Int) {
        acceptsDrafts = false
        chatCache.clear()
        teamProfileCache.clear()
        for name in ["cursor", "draftText", "hasConversation", "hasStartedChat",
                     "conversationStatus", "lastMessageAt", "pushActive", "unreadPolling", "pendingActionClicks",
                     "actionClickOutcomes"] { defaults?.removeObject(forKey: key(name)) }
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
        get {
            registrar.access(self, keyPath: \.pushActive)
            return defaults?.object(forKey: key("pushActive")) as? Bool
        }
        set { registrar.withMutation(of: self, keyPath: \.pushActive) { defaults?.set(newValue, forKey: key("pushActive")) } }
    }

    /// "No thanks" on the notification card, for this device and App ID; logout and chat resets keep it.
    var pushPromptDeclined: Bool {
        get {
            registrar.access(self, keyPath: \.pushPromptDeclined)
            return defaults?.bool(forKey: deviceScope + ".pushPromptDeclined") ?? false
        }
        set {
            registrar.withMutation(of: self, keyPath: \.pushPromptDeclined) {
                defaults?.set(newValue, forKey: deviceScope + ".pushPromptDeclined")
            }
        }
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

    /// The last App Store state of each subscription group, so only a change is reported to automations.
    var subscriptionStates: [String: SubscriptionState] {
        get {
            let stored = defaults?.dictionary(forKey: key("subscriptionStates")) as? [String: String] ?? [:]
            return stored.compactMapValues(SubscriptionState.init(rawValue:))
        }
        set { defaults?.set(newValue.mapValues(\.rawValue), forKey: key("subscriptionStates")) }
    }

    var lastLimitCheck: Date? {
        get { defaults?.object(forKey: key("lastLimitCheck")) as? Date }
        set { defaults?.set(newValue, forKey: key("lastLimitCheck")) }
    }

    var pendingActionClicks: [String] {
        get { defaults?.stringArray(forKey: key("pendingActionClicks")) ?? [] }
        set { if acceptsDrafts { defaults?.set(newValue, forKey: key("pendingActionClicks")) } }
    }

    /// Link tap results by message ID, beside the queue so its stored format stays a plain list.
    var actionClickOutcomes: [String: String] {
        get { defaults?.dictionary(forKey: key("actionClickOutcomes")) as? [String: String] ?? [:] }
        set { if acceptsDrafts { defaults?.set(newValue, forKey: key("actionClickOutcomes")) } }
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
        teamProfileCache.clear()
        for name in ["chatRevision", "cursor", "pending", "draftText", "hasConversation", "hasStartedChat",
                     "conversationStatus", "lastMessageAt", "pushActive", "unreadPolling", "pendingActionClicks",
                     "actionClickOutcomes", "cooldowns", "lastLimitCheck", "subscriptionStates"] { defaults?.removeObject(forKey: key(name)) }
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
