import SwiftUI

extension ChatModel {
    func load(recheckLimits: Bool = false) async {
        guard let session, current, session.store.hasStartedChat, session.halt == nil, session.retries["load"]?.stopped != true else { return }
        // Another GET holds the fetch, perhaps one a close just cancelled that is still unwinding: this load runs once
        // it ends, with the limits recheck if any of the waiting loads asked for it. A load whose own chat already
        // ended (a cancelled opening that only now gets to run) leaves nothing behind.
        guard !loading else {
            if !Task.isCancelled { loadAfterFetch = (loadAfterFetch ?? false) || recheckLimits }
            return
        }
        guard session.isRegistered else {
            if recheckLimits { resumeTransientFailures() }
            return
        }
        let permissionRevision = sendingPermissionRevision
        let cachedIds = Set(messages.filter { $0.seq != nil }.map(\.id))
        loading = true; isLoading = true
        // This load starts after any signal that still waits for its poll, so its answer covers that poll.
        pollAfterFetch = false
        defer { isLoading = false; fetched() }
        do {
            if let delay = session.retries["load"]?.delay { try await Task.sleep(for: delay) }
            try await session.update()
            guard current, !Task.isCancelled,
                  UIApplication.shared.applicationState == .active else { return }
            let generation = Reception.shared.readGeneration
            let knewConversation = session.store.hasConversation
            let checked = recheckLimits && isWatched ? session.cooldowns.beginRecheck() : [:]
            let path = checked.isEmpty ? "conversation" : "conversation?limits=1"
            let response: ConversationResponse = try await session.api.request(path, authenticated: true)
            guard current, !Task.isCancelled else { return }
            guard generation == Reception.shared.readGeneration else { reloadAfterStaleGet(); return }
            // The device learned of its conversation while this answer was on its way (a push, an unread refresh, an
            // automation): the answer is older and would clear the chat, so the chat loads again instead.
            if response.conversation == nil, session.store.hasConversation, !knewConversation { reloadAfterStaleGet(); return }
            let found = response.conversation != nil && !session.store.hasConversation
            session.store.hasConversation = response.conversation != nil
            if let push = response.push { session.store.pushActive = push }
            if let device = response.device { updateSendingPermission(device, revision: permissionRevision) }
            let incomingSequences = Set(response.messages.compactMap(\.seq))
            messages.removeAll { message in
                cachedIds.contains(message.id) && message.seq.map { !incomingSequences.contains($0) } == true
            }
            team = Dictionary((response.team ?? []).map { ($0.id, $0) }) { first, _ in first }
            let arriving = Reception.shared.automations.takeOpenedChat() ? Self.arriving(in: response.messages, cached: cachedIds) : nil
            merge(response.messages.filter { $0.id != arriving?.id })
            if response.messages.isEmpty { saveMessages() }
            // A reveal cut short (a close, a background, a reset) did not show the message: stop before the read
            // cursor moves past it, so the next load or poll brings it.
            if let arriving { guard await reveal(arriving) else { return } }
            if recheckLimits, isWatched {
                if !checked.isEmpty { session.cooldowns.applyRecheck(response.limits, checked: checked) }
                resumeLimitHeldMessages()
            }
            resumeTransientFailures()
            try await markRead(target: processedReadTarget(
                conversationId: response.conversation?.id, hasConversation: response.conversation != nil,
                boundedRead: response.boundedRead, messages: response.messages))
            session.retries["load"] = nil
            // The stream needs a conversation, so an open chat that had none listens from now on.
            if found, isChatActive { startPolling() }
        } catch {
            if !Task.isCancelled, session.halt == nil { session.retries["load", default: RetryState()].failed(error) }
            report(error)
            if recheckLimits, Self.isRecoverableSubmissionFailure(error) || (error as? ReceptionAPIError)?.isCooldown == true {
                resumeTransientFailures()
            }
        }
    }

    /// A GET ended; a load or a poll asked for meanwhile runs now. A load that starts covers the poll.
    func fetched() {
        loading = false
        if !current || !isVisible { loadAfterFetch = nil }
        if let recheck = loadAfterFetch {
            // A reload that is already scheduled is that load and takes the limits recheck with it.
            guard reloadTask == nil else { return }
            loadAfterFetch = nil
            followUp = Task { [weak self] in
                await self?.load(recheckLimits: recheck)
                // A load that was refused (its retry budget, a halt) covered no poll: the poll runs after all.
                if let self, !Task.isCancelled, !self.loading, self.pollAfterFetch { self.fetched() }
            }
            return
        }
        guard pollAfterFetch else { return }
        pollAfterFetch = false
        guard current, isChatActive else { return }
        followUp = Task { [weak self] in await self?.poll() }
    }

    /// The device learned that its conversation exists while the chat is open and knew of none: the team or an
    /// automation wrote first, a scheduled automation's message arrived, a push named it. The chat loads it, then
    /// listens; a close, background, logout or deletion meanwhile ends both (`stopPolling`).
    func conversationStarted() {
        guard isChatActive, conversationStart == nil else { return }
        conversationStart = Task { [weak self] in
            await self?.load()
            guard let self, !Task.isCancelled else { return }
            self.conversationStart = nil
            if self.isChatActive { self.startPolling() }
        }
    }

    /// The newest message, when it is a team message this chat hasn't shown yet.
    private static func arriving(in messages: [Message], cached: Set<String>) -> Message? {
        guard let newest = messages.max(by: { ($0.seq ?? 0) < ($1.seq ?? 0) }),
              newest.sender == "AGENT", !cached.contains(newest.id) else { return nil }
        return newest
    }

    /// The team's typing dots for a moment, then the message, the way a reply arrives while the chat is open.
    /// False when the chat ended meanwhile and the message was not shown.
    private func reveal(_ message: Message) async -> Bool {
        setTyping(true)
        try? await Task.sleep(for: Theme.automationTypingDuration)
        guard current, !Task.isCancelled else { return false }
        withAnimation(Theme.messageAnimation) { merge([message]) }
        return true
    }
}
