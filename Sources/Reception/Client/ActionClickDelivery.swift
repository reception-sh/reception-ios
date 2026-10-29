import Foundation

/// What became of a link card tap; review and paywall receipts carry none.
internal enum ActionOutcome: String {
    case handled, opened, failed
}

@MainActor
internal extension DeviceSession {
    func recordActionClick(_ messageId: String, outcome: ActionOutcome? = nil) {
        guard !invalidated else { return }
        if !store.pendingActionClicks.contains(messageId) {
            store.pendingActionClicks.append(messageId)
        }
        // A queued success is not replaced by a later failure; the service keeps the better result too.
        if let outcome, outcome != .failed || store.actionClickOutcomes[messageId] == nil {
            store.actionClickOutcomes[messageId] = outcome.rawValue
        }
        flushActionClicks()
    }

    func flushActionClicks() {
        guard !invalidated, halt == nil, actionClickTask == nil, !store.pendingActionClicks.isEmpty,
              isRegistered else { return }
        actionClickTask = Task {
            defer { actionClickTask = nil }
            while !invalidated, halt == nil, !Task.isCancelled, let messageId = store.pendingActionClicks.first {
                let key = "action:" + messageId
                guard retries[key]?.stopped != true else { return }
                if let delay = retries[key]?.delay {
                    do { try await Task.sleep(for: delay) } catch { return }
                }
                guard !Task.isCancelled, halt == nil else { return }
                let outcome = store.actionClickOutcomes[messageId]
                do {
                    struct Payload: Encodable { let messageId: String; let outcome: String? }
                    let _: EmptyResponse = try await api.request("conversation/action-click", method: "POST", authenticated: true,
                        body: ReceptionAPI.encode(Payload(messageId: messageId, outcome: outcome)))
                    guard !invalidated else { return }
                    actionClickFinished(messageId, outcome: outcome)
                } catch let error as ReceptionAPIError where error.status == 404 && error.code == "action_not_found" {
                    guard !invalidated else { return }
                    actionClickFinished(messageId, outcome: outcome)
                } catch {
                    if !invalidated, self === Reception.shared.session {
                        _ = Reception.shared.chatModel().handleReset(error)
                    }
                    guard !invalidated, halt == nil, !Task.isCancelled else { return }
                    retries[key, default: RetryState()].failed(error)
                    return
                }
            }
        }
    }

    /// A tap recorded while the request was in flight keeps the entry, so its newer outcome is sent next.
    private func actionClickFinished(_ messageId: String, outcome: String?) {
        guard store.actionClickOutcomes[messageId] == outcome else { return }
        store.pendingActionClicks.removeAll { $0 == messageId }
        store.actionClickOutcomes[messageId] = nil
    }
}
