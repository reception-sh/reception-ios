import Foundation
import Observation

@MainActor @Observable
internal final class AppearanceConfiguration {
    private(set) var active: RemoteAppearance?
    private var latest: AppearanceEnvelope?
    private var api: ReceptionAPI?
    private var cache: AppearanceCache?
    private var etag: String?
    private var lastAttempt: Date?
    private var generation = UUID()
    private var task: Task<Void, Never>?
    private var retry = RetryState()

    func configure(api: ReceptionAPI, scope: String) {
        task?.cancel(); task = nil
        generation = UUID()
        self.api = api
        cache = AppearanceCache(scope: scope)
        latest = cache?.load()
        active = latest?.appearance
        etag = nil
        lastAttempt = nil
        retry = RetryState()
    }

    func resumed() {
        retry = RetryState()
        lastAttempt = nil
    }

    func becameActive() {
        if retry.stopped, retry.attempts >= 8 { lastAttempt = nil }
        retry.foreground()
    }

    func activate() { active = latest?.appearance }

    func refreshWhileActive() async {
        while !Task.isCancelled {
            guard Reception.shared.usesRemoteAppearance, Reception.shared.session?.halt == nil, !retry.stopped else { return }
            await refresh()
            guard !retry.stopped, Reception.shared.session?.halt == nil else { return }
            do { try await Task.sleep(for: retry.delay ?? .seconds(300)) } catch { return }
        }
    }

    func refresh() async {
        if let task { await task.value; return }
        guard Reception.shared.session?.halt == nil, !retry.stopped, var api else { return }
        if let next = retry.nextAttempt {
            guard Date() >= next else { return }
        } else if let lastAttempt, Date().timeIntervalSince(lastAttempt) < 300 { return }
        lastAttempt = Date()
        api.session = Reception.shared.session
        let generation = generation
        let etag = etag
        let task = Task { [weak self] in
            do {
                let response = try await api.appearance(etag: etag)
                guard let self, self.generation == generation, !Task.isCancelled else { return }
                if let value = response.value {
                    guard value.schemaVersion == 1, value.revision >= 0 else {
                        Log.error("Remote appearance fetch failed, HTTP 200 invalid_appearance")
                        return
                    }
                    latest = value
                    cache?.save(value)
                    Log.debug("Remote appearance refreshed, revision \(value.revision)")
                } else {
                    Log.debug("Remote appearance unchanged")
                }
                retry = RetryState()
                self.etag = response.etag ?? etag
                // Freeze the visible chat; the next opening activates this validated snapshot.
            } catch let error as ReceptionAPIError {
                guard let self, self.generation == generation, !Task.isCancelled else { return }
                if error.code != "cancelled", error.code != "session_halted" {
                    Log.error("Remote appearance fetch failed, HTTP \(error.status) \(error.code)")
                }
                api.session?.recordFailure(error)
                if api.session?.halt == nil { retry.failed(error) }
            } catch {
                guard let self, self.generation == generation, !Task.isCancelled else { return }
                retry.failed(error)
                Log.error("Remote appearance fetch failed, HTTP 0 connection_failed")
            }
        }
        self.task = task
        await task.value
        if self.generation == generation { self.task = nil }
    }
}
