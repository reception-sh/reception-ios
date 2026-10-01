import UIKit

@MainActor
internal final class LogoutRevocations: NSObject {
    private struct Entry: Codable, Hashable {
        let appId: String
        let sessionSecret: String
    }
    private let account = "pendingSessionRevocations"
    private var entries: [Entry] = []
    private var loaded = false
    private var task: Task<Void, Never>?
    private var taskID: UUID?
    private var retries: [Entry: RetryState] = [:]

    override init() {
        super.init()
        load()
        NotificationCenter.default.addObserver(self, selector: #selector(becameActive),
            name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(suspend),
            name: UIApplication.didEnterBackgroundNotification, object: nil)
    }

    /// A queue that cannot be read yet (before the first unlock) is merged later, never overwritten.
    private func load() {
        guard !loaded else { return }
        switch KeychainStore.read(account: account) {
        case .unavailable: return
        case .missing: loaded = true
        case .value(let value):
            let saved = (try? JSONDecoder().decode([Entry].self, from: Data(value.utf8))) ?? []
            entries = saved + entries.filter { !saved.contains($0) }
            loaded = true
        }
        if !entries.isEmpty { persist() }
    }

    func enqueue(api: ReceptionAPI, sessionSecret: String) {
        load()
        let entry = Entry(appId: api.appId, sessionSecret: sessionSecret)
        if !entries.contains(entry) { entries.append(entry); persist() }
        resume()
    }

    @objc private func becameActive() {
        for entry in retries.keys { retries[entry]?.foreground() }
        resume()
    }

    func resumed(api: ReceptionAPI) {
        for entry in entries where entry.appId == api.appId {
            retries[entry] = nil
        }
        resume()
    }

    @objc func resume() {
        load()
        guard task == nil, !entries.isEmpty,
              UIApplication.shared.applicationState == .active else { return }
        let id = UUID()
        taskID = id
        task = Task {
            defer { if taskID == id { task = nil; taskID = nil } }
            while !Task.isCancelled {
                let ready = entries.filter { retries[$0]?.stopped != true }
                guard !ready.isEmpty else { return }
                for entry in ready {
                    guard !Task.isCancelled else { return }
                    guard (retries[entry]?.nextAttempt ?? .distantPast) <= Date() else { continue }
                    struct Input: Encodable { let sessionSecret: String }
                    let api = ReceptionAPI(appId: entry.appId)
                    do {
                        let _: EmptyResponse = try await api.request("devices/me/logout", method: "POST",
                            body: ReceptionAPI.encode(Input(sessionSecret: entry.sessionSecret)), expectedStatus: 200)
                        Log.debug("Session revocation completed")
                    } catch {
                        guard !Task.isCancelled else { return }
                        let failure = error as? ReceptionAPIError
                        let description = "HTTP \(failure?.status ?? 0) \(failure?.code ?? "connection_failed")"
                        if ReceptionAPIError.isTransient(error) {
                            Log.error("Session revocation failed, \(description), will retry")
                            retries[entry, default: RetryState()].failed(error)
                            continue
                        }
                        // Logout answers 200 for unknown or revoked sessions, so other errors cannot improve.
                        Log.error("Session revocation dropped, \(description)")
                    }
                    entries.removeAll { $0 == entry }
                    retries[entry] = nil
                    persist()
                }
                let dates = entries.filter { retries[$0]?.stopped != true }.compactMap { retries[$0]?.nextAttempt }
                guard let next = dates.min() else { return }
                do { try await Task.sleep(for: .seconds(max(0, next.timeIntervalSinceNow))) } catch { return }
            }
        }
    }

    @objc private func suspend() {
        task?.cancel()
        task = nil
        taskID = nil
    }

    private func persist() {
        guard loaded, let data = try? JSONEncoder().encode(entries),
              let value = String(data: data, encoding: .utf8) else { return }
        // Retain in-memory work if secure storage is temporarily unavailable.
        _ = KeychainStore.save(value, account: account)
    }
}
