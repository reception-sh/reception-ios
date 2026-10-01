import Foundation

@MainActor
internal extension DeviceSession {
    func recordActionClick(_ messageId: String) {
        guard !invalidated else { return }
        if !store.pendingActionClicks.contains(messageId) {
            store.pendingActionClicks.append(messageId)
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
                do {
                    struct Payload: Encodable { let messageId: String }
                    let _: EmptyResponse = try await api.request("conversation/action-click", method: "POST", authenticated: true,
                        body: ReceptionAPI.encode(Payload(messageId: messageId)))
                    guard !invalidated else { return }
                    store.pendingActionClicks.removeAll { $0 == messageId }
                } catch let error as ReceptionAPIError where error.status == 404 && error.code == "action_not_found" {
                    guard !invalidated else { return }
                    store.pendingActionClicks.removeAll { $0 == messageId }
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
}
