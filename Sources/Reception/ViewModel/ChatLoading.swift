import SwiftUI

extension ChatModel {
    func load(recheckLimits: Bool = false) async {
        guard !loading, let session, current, session.store.hasStartedChat, session.halt == nil, session.retries["load"]?.stopped != true else { return }
        guard session.isRegistered else {
            if recheckLimits { resumeTransientFailures() }
            return
        }
        let permissionRevision = sendingPermissionRevision
        let cachedIds = Set(messages.filter { $0.seq != nil }.map(\.id))
        loading = true; isLoading = true
        defer { loading = false; isLoading = false }
        do {
            if let delay = session.retries["load"]?.delay { try await Task.sleep(for: delay) }
            try await session.update()
            guard current, !Task.isCancelled,
                  UIApplication.shared.applicationState == .active else { return }
            let generation = Reception.shared.readGeneration
            let checked = recheckLimits && isWatched ? session.cooldowns.beginRecheck() : [:]
            let path = checked.isEmpty ? "conversation" : "conversation?limits=1"
            let response: ConversationResponse = try await session.api.request(path, authenticated: true)
            guard current, !Task.isCancelled else { return }
            guard generation == Reception.shared.readGeneration else { reloadAfterStaleGet(); return }
            session.store.hasConversation = response.conversation != nil
            if let device = response.device { updateSendingPermission(device, revision: permissionRevision) }
            let incomingSequences = Set(response.messages.compactMap(\.seq))
            messages.removeAll { message in
                cachedIds.contains(message.id) && message.seq.map { !incomingSequences.contains($0) } == true
            }
            team = Dictionary((response.team ?? []).map { ($0.id, $0) }) { first, _ in first }
            let arriving = Reception.shared.automations.takeOpenedChat() ? Self.arriving(in: response.messages, cached: cachedIds) : nil
            merge(response.messages.filter { $0.id != arriving?.id })
            if response.messages.isEmpty { saveMessages() }
            if let arriving { await reveal(arriving) }
            if recheckLimits, isWatched {
                if !checked.isEmpty { session.cooldowns.applyRecheck(response.limits, checked: checked) }
                resumeLimitHeldMessages()
            }
            resumeTransientFailures()
            try await markRead(target: processedReadTarget(
                conversationId: response.conversation?.id, hasConversation: response.conversation != nil,
                boundedRead: response.boundedRead, messages: response.messages))
            session.retries["load"] = nil
        } catch {
            if !Task.isCancelled, session.halt == nil { session.retries["load", default: RetryState()].failed(error) }
            report(error)
            if recheckLimits, Self.isRecoverableSubmissionFailure(error) || (error as? ReceptionAPIError)?.isCooldown == true {
                resumeTransientFailures()
            }
        }
    }

    /// The newest message, when it is a team message this chat hasn't shown yet.
    private static func arriving(in messages: [Message], cached: Set<String>) -> Message? {
        guard let newest = messages.max(by: { ($0.seq ?? 0) < ($1.seq ?? 0) }),
              newest.sender == "AGENT", !cached.contains(newest.id) else { return nil }
        return newest
    }

    /// The team's typing dots for a moment, then the message, the way a reply arrives while the chat is open.
    private func reveal(_ message: Message) async {
        setTyping(true)
        try? await Task.sleep(for: Theme.automationTypingDuration)
        guard current, !Task.isCancelled else { return }
        withAnimation(Theme.messageAnimation) { merge([message]) }
    }
}
