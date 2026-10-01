import UIKit

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
            merge(response.messages)
            if response.messages.isEmpty { saveMessages() }
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
}
