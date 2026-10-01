import UIKit

@MainActor
internal final class DeviceSession {
    private(set) var api: ReceptionAPI
    let attachmentImages = AttachmentImages()
    let store: DeviceStore
    let cooldowns: ServerCooldowns
    /// Short-lived bearer token, never persisted; a missing token is refreshed on first use.
    var accessToken: String?
    /// Memory copy of the Keychain item. A new registration is used only once it is stored.
    var credentials: SessionCredentials?
    var credentialsUnsaved = false
    var registration: Task<String, Error>?
    var refresh: Task<String, Error>?
    var refreshBackoff: Task<Void, Error>?
    var refreshFailures = 0
    let refreshSleep: (Duration) async throws -> Void
    var actionClickTask: Task<Void, Never>?
    private var updateGeneration = 0
    private var preferenceRetryID: UUID?
    private var updateTask: Task<Void, Error>?
    private var preferenceRetryTask: Task<Void, Never>?
    var synchronizedPaywalls: [ReceptionPaywall]?
    var synchronizedLanguage: String?
    var synchronizedAppBadge: Bool?
    private(set) var invalidated = false
    enum HaltReason { case appUnavailable, blocked }
    private(set) var halt: HaltReason?
    var registrationAllowed = false
    var preferenceRetry = RetryState()
    var retries: [String: RetryState] = [:]

    init(api: ReceptionAPI, store: DeviceStore, halt: HaltReason? = nil,
         refreshSleep: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
         now: @escaping () -> Date = Date.init) {
        var api = api
        api.chatRevision = store.chatRevision
        self.api = api; self.store = store
        cooldowns = ServerCooldowns(store: store, now: now)
        self.halt = halt
        self.refreshSleep = refreshSleep
        self.api.session = self
        cooldowns.onChange = { [weak self] in self?.cooldownsChanged() }
        // Old device registrations alone do not prove that the user used support.
        if !store.hasStartedChat, !store.chatCache.load().isEmpty {
            store.hasStartedChat = true
        }
    }

    func update() async throws {
        guard !invalidated else { throw ReceptionAPIError(code: "cancelled", status: 0) }
        guard halt == nil || RequestContext.probe?.available == true else {
            Log.debug("Request skipped, session halted")
            throw ReceptionAPIError(code: "session_halted", status: 0)
        }
        updateGeneration &+= 1
        if let updateTask { return try await updateTask.value }
        let task = Task {
            defer { updateTask = nil }
            struct Response: Decodable { let verifiedUserId: String? }
            var sentGeneration: Int
            var withoutIdentityToken = false
            var resend = false
            repeat {
                resend = false
                try Task.checkCancellation()
                guard !invalidated else { throw ReceptionAPIError(code: "cancelled", status: 0) }
                sentGeneration = updateGeneration
                let language = ReceptionLocalization.appLanguage
                let badge = Reception.shared.updatesAppBadge
                let paywalls = Reception.shared.availablePaywalls
                let identityToken = withoutIdentityToken ? nil : unsentIdentityToken
                let response: Response
                do {
                    response = try await api.request("devices/me", method: "PATCH", authenticated: true,
                        body: DeviceInfo.payload(identity: store.pending, identityToken: identityToken?.value))
                } catch let error as ReceptionAPIError where error.rejectsIdentityToken {
                    guard let identityToken else { throw error }
                    identityRejected(identityToken, error)
                    guard !invalidated else { throw ReceptionAPIError(code: "cancelled", status: 0) }
                    // A rejected token never blocks the chat: this update is sent once more without it.
                    withoutIdentityToken = true
                    resend = true
                    continue
                }
                try Task.checkCancellation()
                guard !invalidated else { throw ReceptionAPIError(code: "cancelled", status: 0) }
                storeVerifiedUserId(response.verifiedUserId)
                if let identityToken { Reception.shared.identityTokenSent(identityToken) }
                synchronizedPaywalls = paywalls
                synchronizedLanguage = language
                synchronizedAppBadge = badge
                // Preference changes during a request must follow its older values.
            } while resend || preferencesNeedSync || sentGeneration != updateGeneration
        }
        updateTask = task
        do {
            try await task.value
            Log.debug("Device updated")
            flushActionClicks()
        }
        catch {
            // A lost response can leave the server with a value we did not acknowledge.
            synchronizedAppBadge = nil
            throw error
        }
    }

    func preferencesChanged() {
        preferenceRetry = RetryState()
        suspendPreferenceRetry()
        retryPreferencesIfNeeded()
    }

    private var preferencesNeedSync: Bool {
        synchronizedPaywalls != Reception.shared.availablePaywalls || synchronizedLanguage != ReceptionLocalization.appLanguage || synchronizedAppBadge != Reception.shared.updatesAppBadge
    }

    private func retryPreferencesIfNeeded() {
        guard !invalidated, halt == nil, isRegistered, !preferenceRetry.stopped, store.hasStartedChat, preferencesNeedSync, preferenceRetryTask == nil,
              UIApplication.shared.applicationState == .active else { return }
        let id = UUID()
        preferenceRetryID = id
        preferenceRetryTask = Task {
            defer {
                if preferenceRetryID == id { preferenceRetryTask = nil; preferenceRetryID = nil }
            }
            while !invalidated, halt == nil, !Task.isCancelled, preferencesNeedSync, !preferenceRetry.stopped {
                if let delay = preferenceRetry.delay {
                    do { try await Task.sleep(for: delay) } catch { return }
                }
                guard !Task.isCancelled, halt == nil else { return }
                do { try await update(); preferenceRetry = RetryState() }
                catch {
                    guard !invalidated, !Task.isCancelled else { return }
                    if self === Reception.shared.session, Reception.shared.chatModel().handleReset(error) { return }
                    guard halt == nil else { return }
                    preferenceRetry.failed(error)
                }
            }
        }
    }

    func requestSucceeded(probe: Bool) {
        guard !invalidated, probe, halt != nil else { return }
        halt = nil
        preferenceRetry = RetryState()
        Log.debug("Session resumed")
        if self === Reception.shared.session { Reception.shared.sessionResumed() }
    }

    func recordFailure(_ error: Error) {
        guard !invalidated, let error = error as? ReceptionAPIError else { return }
        let reason: HaltReason
        switch (error.status, error.code) {
        case (401, "invalid_app_id"), (403, "app_disabled"): reason = .appUnavailable
        case (403, "blocked"): reason = .blocked
        default: return
        }
        guard halt != reason else { Log.debug("Request skipped, session halted"); return }
        halt = reason
        suspendPreferenceRetry()
        actionClickTask?.cancel()
        if self === Reception.shared.session {
            Reception.shared.chatModel().suspendAutomaticRequests()
            Reception.shared.unreadMonitor.reschedule()
        }
        switch reason {
        case .appUnavailable where error.code == "invalid_app_id":
            Log.error("Session halted, HTTP 401 invalid_app_id, check the App ID")
        case .appUnavailable: Log.error("Session halted, HTTP 403 app_disabled")
        case .blocked: Log.info("Session halted, HTTP 403 blocked")
        }
    }

    func becameActive() {
        preferenceRetry.foreground()
        for key in retries.keys { retries[key]?.foreground() }
        if halt == nil {
            retryPreferencesIfNeeded()
            if self === Reception.shared.session {
                Reception.shared.chatModel().retryFailedAutomatically()
                Reception.shared.chatModel().startStream()
            }
        }
    }

    func suspendPreferenceRetry() {
        preferenceRetryTask?.cancel()
        preferenceRetryTask = nil
        preferenceRetryID = nil
    }

    func deactivate() {
        invalidated = true
        credentialsUnsaved = false
        attachmentImages.invalidate()
        cooldowns.invalidate()
        registration?.cancel()
        refresh?.cancel()
        refreshBackoff?.cancel()
        refreshBackoff = nil
        updateTask?.cancel()
        suspendPreferenceRetry()
        actionClickTask?.cancel()
    }
    func invalidate() { deactivate(); store.clear() }
}
