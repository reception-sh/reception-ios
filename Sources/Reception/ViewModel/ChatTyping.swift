import Foundation

extension ChatModel {
    func sendTyping(_ active: Bool) {
        userTypingIdle?.cancel(); userTypingIdle = nil
        guard current, let session, session.store.hasConversation,
              !active || (isChatActive && canSend) else { return }
        if active {
            userTypingIdle = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(1.5)) } catch { return }
                self?.sendTyping(false)
            }
            if userIsTyping && Date().timeIntervalSince(lastUserTyping) < 3 { return }
        } else if !userIsTyping { return }
        userIsTyping = active
        lastUserTyping = active ? Date() : .distantPast
        let previous = userTypingTask
        userTypingTask = Task {
            await previous?.value
            guard self.current, !Task.isCancelled else { return }
            do {
                struct Input: Encodable { let typing: Bool }
                let _: EmptyResponse = try await session.api.request("conversation/typing", method: "POST",
                    authenticated: true, body: ReceptionAPI.encode(Input(typing: active)))
            } catch { _ = self.handleReset(error) }
        }
    }
}
