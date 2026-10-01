import SwiftUI

extension ChatModel {
    func send(text: String, images: [UIImage]) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend, cooldownAllowsSend(photos: !images.isEmpty),
              (!text.isEmpty || !images.isEmpty), text.utf16.count <= 4000, images.count <= 5 else { return }
        let message = Message(id: UUID().uuidString, sender: "USER", text: text,
                              attachments: [], createdAt: Date(), status: .sending, images: images)
        withAnimation(Theme.messageAnimation) { messages.append(message) }
        session?.store.hasStartedChat = true
        saveMessages()
        submit(message.id, userInitiated: true)
        if isChatActive { startPolling() }
        Reception.shared.unreadMonitor.setActive(UIApplication.shared.applicationState == .active)
    }
    func retry(messageId: String) {
        guard canSend, let index = messages.firstIndex(where: { $0.id == messageId }),
              messages[index].status == .failed, cooldown(for: messages[index]) == nil else { return }
        if automaticRetry?.messageId == messageId { cancelAutomaticRetry() }
        withAnimation(Theme.messageAnimation) {
            messages[index].status = .sending
            messages[index].awaitsManualRetry = false
            messages[index].retryAfterLimitRelease = false
            messages[index].retryAfterTransientFailure = false
        }
        saveMessages()
        session?.retries[messageId] = RetryState()
        submit(messageId, userInitiated: true)
    }
    func submit(_ id: String, userInitiated: Bool = false) {
        guard canSend, sends[id] == nil, userInitiated || session?.halt == nil else { return }
        if userInitiated { session?.retries[id] = RetryState() }
        schedulePending(id)
        sends[id] = Task { [weak self] in
            guard let self else { return }
            defer { self.clearPending(id) }
            await RequestContext.$probe.withValue(userInitiated ? RequestProbe() : nil) {
                await self.deliver(id)
            }
            self.sends[id] = nil
            self.retryFailedAutomatically()
        }
    }
    private func deliver(_ id: String) async {
        guard let session, current, let draft = messages.first(where: { $0.id == id && $0.seq == nil }) else { return }
        defer { uploadProgress = nil }
        var postingMessage = false
        let scopes = cooldownScopes(for: draft)
        do {
            guard draft.images.count >= draft.attachmentIds.count,
                  draft.images.count == (draft.expectedImageCount ?? draft.images.count) else {
                throw ReceptionAPIError(code: "invalid_image", status: 0)
            }
            // A known wait holds the whole send, so it spends neither request nor upload budget.
            try session.admit(scopes)
            // This cached submission already carries the user's send intent; drafts never grant registration.
            if draft.retryAfterTransientFailure, isWatched { session.registrationAllowed = true }
            // With a credential, probe the requested send itself: a successful PATCH cannot prove an unblock.
            if session.halt == nil || !session.isRegistered { try await session.update() }
            var attachments = draft.attachmentIds
            for index in attachments.count..<draft.images.count {
                try session.admit(scopes)
                uploadProgress = Double(index) / Double(draft.images.count)
                let attachment: String
                do {
                    attachment = try await ImageUploader.upload(draft.images[index], messageId: id, index: index,
                                                                session: session) { [weak self] fraction in
                        self?.uploadProgress = (Double(index) + fraction) / Double(draft.images.count)
                    }
                } catch let error as ReceptionAPIError {
                    if !error.isCooldown { Log.error("Image upload failed, HTTP \(error.status) \(error.code)") }
                    throw error
                }
                guard current else { return }
                attachments.append(attachment)
                if let index = messages.firstIndex(where: { $0.id == id }) { messages[index].attachmentIds = attachments; saveMessages() }
                uploadProgress = Double(attachments.count) / Double(draft.images.count)
            }
            guard canSend else { restoreBlockedMessage(id); return }
            struct Input: Encodable { let clientId: String; let text: String; let attachmentIds: [String] }
            postingMessage = true
            let response: SendResponse = try await session.api.request("conversation/messages", method: "POST", authenticated: true,
                body: ReceptionAPI.encode(Input(clientId: id, text: draft.text, attachmentIds: attachments)), photos: !attachments.isEmpty)
            guard current else { return }
            Reception.shared.invalidateRead()
            session.store.hasConversation = true
            withAnimation(Theme.messageAnimation) {
                var confirmed = response.message
                confirmed.clientId = confirmed.clientId ?? id
                merge([confirmed], advancesCursor: false)
            }
            if verificationRequired { clearVerificationRequirement() }
            if isChatActive { startPolling() }
            Reception.shared.onEvent?(.messageSent)
            if !draft.images.isEmpty { Reception.shared.onEvent?(.imageSent) }
            session.retries[id] = nil
            limitReleaseRetries.remove(id)
            Log.debug("Message sent")
        } catch {
            if handleReset(error) { return }
            guard current, let index = messages.firstIndex(where: { $0.id == id && $0.seq == nil }) else { return }
            if postingMessage, let error = error as? ReceptionAPIError,
               (error.status == 400 && error.code == "invalid_attachment") || (error.status == 409 && error.code == "upload_incomplete") {
                // Only a rejected message proves that the saved upload mapping cannot be reused.
                messages[index].attachmentIds = []
            }
            if let error = error as? ReceptionAPIError, error.status == 403, error.code == "blocked" {
                disableSending()
            }
            if let error = error as? ReceptionAPIError, error.status == 403, error.code == "verification_required" {
                requireVerification()
            }
            if let error = error as? ReceptionAPIError, error.isCooldown {
                Log.info("Message send held, \(error.retryScope?.rawValue ?? "unknown") paused")
            } else if let error = error as? ReceptionAPIError, error.status > 0 {
                Log.error("Message send failed, HTTP \(error.status) \(error.code)")
            } else {
                Log.error("Message send failed, network error")
                if let code = (error as? ReceptionAPIError)?.urlErrorCode {
                    Log.debug("Message send failed, network error, URLError \(code)")
                }
            }
            withAnimation(Theme.messageAnimation) {
                messages[index].status = .failed
                messages[index].retryAfterTransientFailure = Self.isRecoverableSubmissionFailure(error)
                let cooldown = cooldown(for: messages[index])
                messages[index].heldBy = cooldown?.scope
                messages[index].retryAfterLimitRelease = (error as? ReceptionAPIError)?.retryScope != nil
                    && (error as? ReceptionAPIError)?.retryAfter != nil
                    && session.cooldowns.blocking(cooldownScopes(for: messages[index]).filter { $0 == .messages || $0 == .uploads }) != nil
                // Only a short wait in a watched chat resends by itself; any other wait needs the person again.
                if let cooldown, !(cooldown.automatic && isWatched) {
                    messages[index].awaitsManualRetry = true
                }
            }
            if limitReleaseRetries.contains(id) { pauseLimitReleaseRetries() }
            saveMessages()
            if session.halt == nil { session.retries[id, default: RetryState()].failed(error) }
            report(error)
        }
    }
}
