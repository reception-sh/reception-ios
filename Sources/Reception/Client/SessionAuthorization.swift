import Foundation

extension DeviceSession {
    var isRegistered: Bool { (try? storedCredentials()) != nil }

    /// Memory first, then the Keychain. Throws when the Keychain cannot be read.
    func storedCredentials() throws -> SessionCredentials? {
        if let credentials { return credentials }
        credentials = try store.loadCredentials()
        return credentials
    }

    /// The current access token. Without one in memory it refreshes; only a user's send may register.
    func token() async throws -> String {
        guard !invalidated else { throw ReceptionAPIError(code: "cancelled", status: 0) }
        guard store.hasStartedChat else {
            throw ReceptionAPIError(code: "chat_not_started", status: 0)
        }
        guard halt == nil || RequestContext.probe?.available == true else {
            Log.debug("Request skipped, session halted")
            throw ReceptionAPIError(code: "session_halted", status: 0)
        }
        try persistPendingCredentials()
        if let accessToken { return accessToken }
        if let registration { return try await registration.value }
        if try storedCredentials() != nil { return try await renewedToken(replacing: nil) }
        if RequestContext.probe != nil { registrationAllowed = true }
        guard registrationAllowed else { throw ReceptionAPIError(code: "chat_not_started", status: 0) }
        return try await register()
    }

    /// A token other than `rejected`: one a concurrent refresh already stored, or a new one. Refreshes one at a time.
    func renewedToken(replacing rejected: String?) async throws -> String {
        guard !invalidated else { throw ReceptionAPIError(code: "cancelled", status: 0) }
        if let accessToken, accessToken != rejected { return accessToken }
        if let refresh { return try await refresh.value }
        guard let secret = try storedCredentials()?.sessionSecret else {
            throw ReceptionAPIError(code: "session_revoked", status: 401)
        }
        // A renewal limit fails callers at once instead of holding their requests for the whole wait.
        try admit([.session])
        let task = Task {
            try await refreshBackoff?.value
            try Task.checkCancellation()
            try admit([.session])
            return try await refreshToken(secret: secret)
        }
        refresh = task
        defer { refresh = nil }
        return try await task.value
    }

    /// Keeps registrations and identity changes retryable until their credentials are safely stored.
    func persistPendingCredentials() throws {
        guard !invalidated else { throw ReceptionAPIError(code: "cancelled", status: 0) }
        guard credentialsUnsaved, let credentials else { return }
        try store.save(credentials)
        credentialsUnsaved = false
    }

    private func register() async throws -> String {
        let task = Task { () throws -> String in
            Log.debug("Device registration started")
            struct Response: Decodable { let token: String; let sessionSecret: String; let verifiedUserId: String? }
            let badge = Reception.shared.updatesAppBadge
            let paywalls = Reception.shared.availablePaywalls
            let language = ReceptionLocalization.appLanguage
            let identityToken = stagedIdentityToken
            let response: Response
            do {
                response = try await api.request("devices", method: "POST",
                    body: DeviceInfo.payload(identity: store.pending, identityToken: identityToken?.value, registration: true))
            } catch let error as ReceptionAPIError where error.rejectsIdentityToken {
                // The send fails and keeps Retry; the next registration goes without this token.
                if let identityToken { identityRejected(identityToken, error) }
                throw error
            }
            try Task.checkCancellation()
            guard !invalidated else { throw ReceptionAPIError(code: "cancelled", status: 0) }
            accessToken = response.token
            credentials = SessionCredentials(sessionSecret: response.sessionSecret, verifiedUserId: response.verifiedUserId)
            credentialsUnsaved = true
            if let identityToken { Reception.shared.identityTokenSent(identityToken) }
            try persistPendingCredentials()
            synchronizedPaywalls = paywalls
            synchronizedAppBadge = badge
            synchronizedLanguage = language
            Log.info("Device registered")
            return response.token
        }
        registration = task
        defer { registration = nil }
        return try await task.value
    }

    private func refreshToken(secret: String) async throws -> String {
        struct Input: Encodable { let sessionSecret: String }
        struct Output: Decodable { let token: String }
        do {
            // Part of an already admitted request: blocked devices may refresh, so no halt check here.
            let output: Output = try await api.send("devices/me/token", method: "POST",
                token: nil, body: ReceptionAPI.encode(Input(sessionSecret: secret)))
            guard !invalidated, credentials?.sessionSecret == secret else {
                throw ReceptionAPIError(code: "cancelled", status: 0)
            }
            accessToken = output.token
            refreshFailures = 0
            refreshBackoff = nil
            Log.debug("Access token refreshed")
            return output.token
        } catch let error as ReceptionAPIError where error.status == 401 && error.code == "session_revoked" {
            if !invalidated, credentials?.sessionSecret == secret { sessionRevoked() }
            throw error
        } catch let error as ReceptionAPIError {
            // A server wait becomes the stored session cooldown in requestFailed; other transient failures back off.
            if !invalidated, ReceptionAPIError.isTransient(error), error.retryScope == nil {
                refreshFailures = min(refreshFailures, 6) + 1
                let delay = Backoff.delay(attempt: refreshFailures)
                // The delay belongs to the session: another caller must not bypass a failed refresh's backoff.
                refreshBackoff = Task { [refreshSleep] in try await refreshSleep(delay) }
            }
            requestFailed(error, path: "devices/me/token")
            throw error
        }
    }

    /// The server no longer knows this session: forget it and continue with a fresh one.
    private func sessionRevoked() {
        Log.error("Session revoked, HTTP 401 session_revoked, local session reset")
        accessToken = nil
        credentials = nil
        credentialsUnsaved = false
        if self === Reception.shared.session { Reception.shared.resetChat(revision: 0, deviceDeleted: true) }
    }
}
