import Foundation

extension Reception {
    /// Labels the support device with your user's details. The service shows them as unverified.
    /// Call `logout()` when users switch; this method never resets the chat.
    public func identify(userId: String?, name: String? = nil, email: String? = nil) {
        guard let session else {
            Log.error("identify called before configure, ignored")
            return
        }
        if let userId, let verified = try? session.storedCredentials()?.verifiedUserId, !UserIdentity.matches(verified, userId) {
            Log.error("identify(userId:) does not match the verified user; call logout() when users switch")
        }
        var identity = session.store.pending
        identity.externalUserId = DeviceInputValidation.checked(userId, field: "userId", limit: 255)
        identity.name = DeviceInputValidation.checked(name, field: "name", limit: 200)
        identity.email = DeviceInputValidation.checked(email, field: "email", limit: 254)
        session.store.pending = identity
        Log.debug("Identity staged")
    }

    /// Verifies the signed-in user with a token that your server signs with the identity secret (HS256 JWT with
    /// `user_id` and `exp`). Call it after `configure` on every launch while a user is signed in, and after sign-in.
    /// The token stays in memory. A token for another user logs the previous session out first; it never replaces
    /// `logout()` at sign-out. Rejections arrive as `ReceptionEvent.identityRejected`.
    public func identify(token: String) {
        guard let session else {
            Log.error("identify(token:) called before configure, ignored")
            return
        }
        guard token != lastIdentityToken else {
            Log.debug("Identity token unchanged, ignored")
            return
        }
        lastIdentityToken = token
        guard !token.hasPrefix("ids_") else {
            Log.error("Identity token refused: this is the identity secret, which belongs only on your server")
            return
        }
        guard let identityToken = IdentityToken(token) else {
            Log.error("Identity token ignored, its user_id could not be read")
            return
        }
        let verifiedUserId: String?
        do { verifiedUserId = try session.storedCredentials()?.verifiedUserId }
        catch {
            Log.error("Identity token ignored, secure storage unavailable")
            return
        }
        let unverifiedUserId = session.store.pending.externalUserId
        // A registration or anonymous-to-verified update may still be awaiting its verified ID.
        let sameUser = identityToken.matchesUser(verifiedUserId: verifiedUserId, unverifiedUserId: unverifiedUserId,
                                                 stagedUserId: self.identityToken?.userId)
        guard sameUser else {
            switchUser(to: identityToken)
            return
        }
        // Sent with the next registration or device update (launch, foreground, chat opening, send), never at once:
        // a host that answers every rejection with a new token must not start a request loop.
        self.identityToken = identityToken
        chat?.clearVerificationRequirement()
        Log.debug("Identity token staged")
    }

    public func setMetadata(_ metadata: [String: String]) {
        guard let store = session?.store else {
            Log.error("setMetadata called before configure, ignored")
            return
        }
        var identity = store.pending; identity.metadata = DeviceInputValidation.checked(metadata); store.pending = identity
        Log.debug("Metadata staged")
    }

    /// Another user's token: revoke and reset the previous session, keep only the new token and the push token.
    /// The next send registers the new session.
    internal func switchUser(to token: IdentityToken) {
        Log.info("Signed-in user changed, previous session logged out")
        let pending = session?.store.pending
        logout()
        var identity = DeviceIdentity()
        identity.pushToken = pending?.pushToken
        identity.pushEnvironment = pending?.pushEnvironment
        session?.store.pending = identity
        var unsent = token
        unsent.sent = false
        identityToken = unsent
        lastIdentityToken = token.value
    }

    internal func forgetIdentityToken() {
        identityToken = nil
        lastIdentityToken = nil
    }

    internal func identityTokenSent(_ token: IdentityToken) {
        guard identityToken?.value == token.value else { return }
        identityToken?.sent = true
    }

    internal func identityTokenRejected(_ token: IdentityToken, error: ReceptionError) {
        if identityToken?.value == token.value { identityToken = nil }
        onEvent?(.identityRejected(error))
    }
}
