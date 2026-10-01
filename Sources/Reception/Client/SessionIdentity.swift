import Foundation

extension DeviceSession {
    /// Registrations always carry the staged token, so a new session after a reset stays verified.
    var stagedIdentityToken: IdentityToken? {
        self === Reception.shared.session ? Reception.shared.identityToken : nil
    }

    /// Device updates carry the token only until the service has accepted it.
    var unsentIdentityToken: IdentityToken? {
        stagedIdentityToken.flatMap { $0.sent ? nil : $0 }
    }

    /// The service's value replaces the stored one after every registration and device update.
    func storeVerifiedUserId(_ userId: String?) {
        guard var credentials, !UserIdentity.matches(credentials.verifiedUserId, userId) || credentialsUnsaved else { return }
        credentials.verifiedUserId = userId
        self.credentials = credentials
        credentialsUnsaved = true
        do {
            try persistPendingCredentials()
        } catch {
            Log.error("Verified user not stored, secure storage unavailable")
        }
    }

    /// A rejected token is dropped and reported; a token for another user starts that user's own session.
    func identityRejected(_ token: IdentityToken, _ error: ReceptionAPIError) {
        guard !invalidated, self === Reception.shared.session, stagedIdentityToken?.value == token.value else { return }
        if error.code == "identity_mismatch" {
            Reception.shared.switchUser(to: token)
        } else {
            Reception.shared.identityTokenRejected(token, error: ReceptionError(code: error.code, status: error.status))
        }
    }
}
