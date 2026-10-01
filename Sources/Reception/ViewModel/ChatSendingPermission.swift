import SwiftUI

extension ChatModel {
    func disableSending() {
        if !sendingDisabled { Log.info("Device blocked by the team") }
        sendingPermissionRevision += 1
        sendingDisabled = true
        cancelAutomaticRetry()
    }

    func requireVerification() {
        if !verificationRequired { Log.info("Sending requires a verified user") }
        sendingPermissionRevision += 1
        verificationRequired = true
    }

    /// Local knowledge wins over responses that were already underway, such as after `identify(token:)`.
    func clearVerificationRequirement() {
        sendingPermissionRevision += 1
        verificationRequired = false
    }

    func updateSendingPermission(_ device: ConversationResponse.Device, revision: Int) {
        // A GET started before a rejected POST must not re-enable sending with stale data.
        guard revision == sendingPermissionRevision else { return }
        if let blocked = device.blocked {
            if blocked { disableSending() } else { sendingDisabled = false }
        }
        if let required = device.verificationRequired {
            // A staged token that has not reached the service yet may still lift the requirement.
            let tokenPending = Reception.shared.identityToken.map { !$0.sent } ?? false
            if !required { verificationRequired = false } else if !tokenPending { requireVerification() }
        }
    }

    func restoreBlockedMessage(_ id: String) {
        guard let message = messages.first(where: { $0.id == id }) else { return }
        clearPending(id)
        session?.retries[id] = nil
        composer.text = [message.text, composer.text].filter { !$0.isEmpty }.joined(separator: "\n")
        composer.photos.insert(contentsOf: message.images.map { ComposerModel.Photo(image: $0) }, at: 0)
        composer.hasPhotoError = false
        messages.removeAll { $0.id == id }
        saveMessages()
    }
}
