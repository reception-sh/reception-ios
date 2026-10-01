import Foundation
import Observation

/// Waits the service imposed on this device session, per limit scope. They are stored with the session, so neither
/// foreground, reopening the chat, an explicit retry nor a relaunch skips one. Only a current server check or
/// a session reset can release them early.
@MainActor @Observable
internal final class ServerCooldowns {
    struct Cooldown: Codable, Equatable {
        let scope: RetryScope
        let until: Date
        /// The service asked for at most a minute. Only such waits end in an automatic resend; the original length
        /// decides, so a long wait that is nearly over still needs a manual retry.
        let automatic: Bool
    }

    static let automaticLimit = 60
    private(set) var active: [RetryScope: Cooldown] = [:]
    let now: () -> Date
    /// Called when a wait starts or ends, so connection state and waiting resends can follow.
    @ObservationIgnored var onChange: (() -> Void)?
    private let store: DeviceStore
    private var revisions: [RetryScope: Int] = [:]
    @ObservationIgnored private var expiry: Task<Void, Never>?

    init(store: DeviceStore, now: @escaping () -> Date) {
        self.store = store
        self.now = now
        // A clock set back must not stretch a stored wait beyond the one day the service can ask for.
        let latest = now().addingTimeInterval(TimeInterval(ReceptionAPI.maximumRetryAfter))
        for cooldown in store.cooldowns where cooldown.until > now() {
            active[cooldown.scope] = Cooldown(scope: cooldown.scope, until: min(cooldown.until, latest),
                                              automatic: cooldown.automatic)
        }
        store.cooldowns = Array(active.values)
        scheduleExpiry()
    }

    /// The latest unfinished cooldown among `scopes`. It resends automatically only when all of them allow it.
    /// A clock set back while waiting cannot stretch a wait beyond one day from now.
    func blocking(_ scopes: [RetryScope]) -> Cooldown? {
        let now = now()
        let limit = now.addingTimeInterval(TimeInterval(ReceptionAPI.maximumRetryAfter))
        if active.values.contains(where: { $0.until > limit }) {
            active = active.mapValues {
                Cooldown(scope: $0.scope, until: min($0.until, limit), automatic: $0.automatic)
            }
            store.cooldowns = Array(active.values)
            scheduleExpiry()
        }
        let waits = Set(scopes).compactMap { active[$0] }.filter { $0.until > now }
        guard let latest = waits.max(by: { $0.until < $1.until }) else { return nil }
        return Cooldown(scope: latest.scope, until: latest.until, automatic: waits.allSatisfy(\.automatic))
    }

    func impose(_ scope: RetryScope, seconds: Int) {
        // Even a repeated rejection supersedes an in-flight read of the budgets.
        revisions[scope, default: 0] += 1
        let until = now().addingTimeInterval(TimeInterval(seconds))
        // Retry-After has whole seconds: a report within a second of the known deadline describes the same wait.
        guard until > (active[scope]?.until ?? .distantPast).addingTimeInterval(1) else { return }
        active[scope] = Cooldown(scope: scope, until: until, automatic: seconds <= Self.automaticLimit)
        store.cooldowns = Array(active.values)
        Log.info("Rate limited, \(scope.rawValue) paused for \(seconds)s")
        scheduleExpiry()
        onChange?()
    }

    /// Attached only to an opening/foreground chat load. Failures also spend this local check interval.
    func beginRecheck() -> [RetryScope: Int] {
        let now = now()
        let scopes: [RetryScope] = [.messages, .uploads]
        let held = scopes.filter { scope in
            guard let wait = blocking([scope]) else { return false }
            return !wait.automatic && wait.until.timeIntervalSince(now) > 60
        }
        guard !held.isEmpty else { return [:] }
        if let last = store.lastLimitCheck {
            if last > now { store.lastLimitCheck = now; return [:] }
            guard now.timeIntervalSince(last) >= 60 else { return [:] }
        }
        store.lastLimitCheck = now
        return Dictionary(uniqueKeysWithValues: held.map { ($0, revisions[$0, default: 0]) })
    }

    /// Only explicit, current server answers can shorten a stored wait. They never turn it into a timer resend.
    func applyRecheck(_ limits: ConversationResponse.Limits?, checked: [RetryScope: Int]) {
        for (scope, revision) in checked where revisions[scope, default: 0] == revision {
            guard let seconds = limits?.seconds(for: scope), let wait = active[scope], wait.until > now() else { continue }
            revisions[scope, default: 0] += 1
            if seconds == 0 { active[scope] = nil }
            else { active[scope] = Cooldown(scope: scope, until: now().addingTimeInterval(TimeInterval(seconds)), automatic: false) }
        }
        store.cooldowns = Array(active.values)
        scheduleExpiry()
    }

    func invalidate() {
        expiry?.cancel()
        expiry = nil
        onChange = nil
    }

    /// One timer for the nearest deadline publishes the end of a wait; nothing polls the service.
    private func scheduleExpiry() {
        expiry?.cancel()
        expiry = nil
        let now = now()
        if active.values.contains(where: { $0.until <= now }) {
            active = active.filter { $0.value.until > now }
            store.cooldowns = Array(active.values)
        }
        guard let next = active.values.map(\.until).min() else { return }
        expiry = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(next.timeIntervalSince(now))) } catch { return }
            guard let self, !Task.isCancelled else { return }
            self.scheduleExpiry()
            self.onChange?()
        }
    }
}
