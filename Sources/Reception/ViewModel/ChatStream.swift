import SwiftUI

extension ChatModel {
    func startStream() {
        guard isChatActive, current, let session, session.store.hasConversation, session.halt == nil, session.retries["stream"]?.stopped != true, polling == nil else { return }
        let id = UUID()
        streamID = id
        polling = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.streamID == id {
                    self.polling = nil
                    self.streamID = nil
                    self.streamConnected = false
                }
            }
            while !Task.isCancelled, self.current, self.isChatActive, session.store.hasConversation, session.halt == nil {
                if let delay = session.retries["stream"]?.delay {
                    do { try await Task.sleep(for: delay) } catch { return }
                }
                guard session.halt == nil, session.retries["stream"]?.stopped != true, !Task.isCancelled else { return }
                var failure: Error = URLError(.networkConnectionLost)
                var reconnect = false
                do {
                    guard !Task.isCancelled, self.current, self.isChatActive,
                          UIApplication.shared.applicationState == .active else { return }
                    let bytes = try await session.api.stream("conversation/events")
                    try Task.checkCancellation()
                    guard self.current, self.isChatActive,
                          UIApplication.shared.applicationState == .active else { return }
                    self.streamDidConnect()
                    var lastRefresh = ContinuousClock.now
                    await self.poll()
                    lines: for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard self.current, self.isChatActive,
                              UIApplication.shared.applicationState == .active else { return }
                        switch line {
                        case "data: changed":
                            lastRefresh = .now
                            await self.poll()
                        case ": ping" where lastRefresh.duration(to: .now) >= .seconds(60):
                            lastRefresh = .now
                            await self.poll()
                        case "data: typing": self.setTyping(true)
                        case "data: idle": self.setTyping(false)
                        case "data: reconnect":
                            // The service closes streams with their access token; the next one opens right away.
                            reconnect = true
                            break lines
                        default: continue
                        }
                    }
                } catch {
                    failure = error
                    guard !Task.isCancelled, self.current else { return }
                    if self.handleReset(error) { return }
                    if let error = error as? ReceptionAPIError {
                        if error.code == "cancelled" { return }
                        if error.code == "no_conversation" {
                            session.store.hasConversation = false
                            self.setTyping(false)
                            return
                        }
                    }
                }
                guard !Task.isCancelled, self.current else { return }
                if reconnect { continue }
                self.streamDidDisconnect()
                guard session.halt == nil else { return }
                session.retries["stream", default: RetryState()].failed(failure)
            }
        }
    }

    func cancelStream() {
        streamID = nil
        polling?.cancel(); polling = nil
        streamConnected = false
    }

    func setTyping(_ typing: Bool) {
        typingDismissal?.cancel(); typingDismissal = nil
        withAnimation(Theme.messageAnimation) { isTyping = typing }
        guard typing else { return }
        typingDismissal = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(8)) } catch { return }
            self?.setTyping(false)
        }
    }
}
