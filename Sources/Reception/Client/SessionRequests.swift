import Foundation

extension DeviceSession {
    /// The last check before the network. A known cooldown is checked first, so it never spends the probe that lets
    /// one user action through a halted session.
    func authorizeRequest(_ scopes: [RetryScope] = []) throws -> Bool {
        guard !invalidated else { throw ReceptionAPIError(code: "cancelled", status: 0) }
        try admit(scopes)
        let probe = RequestContext.probe
        let permitted = probe?.available == true
        probe?.available = false
        guard halt == nil || permitted else {
            Log.debug("Request skipped, session halted")
            throw ReceptionAPIError(code: "session_halted", status: 0)
        }
        return halt != nil && permitted
    }

    func requestFailed(_ error: ReceptionAPIError, path: String, method: String? = nil) {
        guard !invalidated, error.code != "cancelled", error.code != "session_halted", !error.isCooldown else { return }
        imposeCooldown(for: error)
        if path == "devices", method == "POST" {
            Log.error("Device registration failed, HTTP \(error.status) \(error.code)")
        } else if path == "devices/me", method == "PATCH" {
            Log.error("Device update failed, HTTP \(error.status) \(error.code)")
        } else if path == "devices/me/token" {
            Log.error("Access token refresh failed, HTTP \(error.status) \(error.code)")
        }
        recordFailure(error)
    }

}
