import SwiftUI
import Network

internal enum ConnectionState { case hidden, offline, connecting, connected, paused }

/// The banner is derived from three facts only: does the device have a network path, is the live
/// stream up, and does a server wait hold it back. Retry attempts never touch it, so it cannot flicker
/// while the app keeps trying.
extension ChatModel {
    func startMonitoring() {
        // Only chats that were used before show connection state; an unused chat stays silent.
        guard pathTask == nil, session?.store.hasStartedChat == true else { return }
        let monitor = NWPathMonitor()
        pathMonitor = monitor
        let updates = AsyncStream<Bool> { continuation in
            monitor.pathUpdateHandler = { continuation.yield($0.status == .satisfied) }
            continuation.onTermination = { _ in monitor.cancel() }
        }
        monitor.start(queue: DispatchQueue(label: "com.reception.sdk.networkPath"))
        pathTask = Task { [weak self] in
            var previous: Bool?
            for await satisfied in updates {
                guard let self, !Task.isCancelled, self.current else { break }
                self.pathSatisfied = satisfied
                // Observe immediately, but keep networking behind the existing chat activation.
                if self.isChatActive, self.session?.store.hasStartedChat == true {
                    if satisfied {
                        // Network is back: drop the backoff and reconnect right away.
                        if previous == false { self.cancelStream() }
                        self.startStream()
                        self.retryFailedAutomatically()
                    } else {
                        self.cancelStream()
                    }
                }
                self.refreshConnection()
                previous = satisfied
            }
        }
    }

    /// Recomputes the banner from the two facts. Safe to call at any time.
    func refreshConnection() {
        guard pathTask != nil else { return }
        // A halted session attempts nothing, so there is no connection state to report.
        if session?.halt != nil {
            linkGrace?.cancel(); linkGrace = nil
            if connection != .hidden { setConnection(.hidden) }
            return
        }
        if pathSatisfied == false {
            linkGrace?.cancel(); linkGrace = nil
            setConnection(.offline)
            return
        }
        guard session?.store.hasConversation == true else {
            linkGrace?.cancel(); linkGrace = nil
            if pathSatisfied == true { setConnection(.hidden) }
            return
        }
        guard !streamConnected else { return }
        // A server wait holds the live connection back; sending stays available.
        if streamPaused {
            linkGrace?.cancel(); linkGrace = nil
            setConnection(.paused)
            return
        }
        // Network is back but the link is not up yet: say so right away.
        if connection == .offline { setConnection(.connecting); return }
        // Link dropped while online: a one-second grace keeps blinks invisible.
        guard connection != .connecting, linkGrace == nil else { return }
        linkGrace = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            guard let self, self.pathTask != nil, !self.streamConnected, self.pathSatisfied != false else { return }
            self.linkGrace = nil
            self.setConnection(.connecting)
        }
    }

    func streamDidConnect() {
        streamConnected = true
        linkGrace?.cancel(); linkGrace = nil
        retryFailedAutomatically()
        guard [.offline, .connecting, .paused].contains(connection) else { return }
        setConnection(.connected)
        connectionDismissal = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(Theme.connectedDuration)) } catch { return }
            guard let self, self.connection == .connected else { return }
            self.setConnection(.hidden)
        }
    }

    func streamDidDisconnect() {
        streamConnected = false
        refreshConnection()
    }

    func report(_ error: Error) {
        if handleReset(error) { return }
        guard current, !Task.isCancelled else { return }
        let apiError = error as? ReceptionAPIError
        guard apiError?.code != "cancelled" else { return }
        if ["connection_failed", "upload_failed"].contains(apiError?.code ?? "") || (apiError?.status ?? 0) >= 500 {
            refreshConnection()
        }
    }

    func setConnection(_ state: ConnectionState) {
        connectionDismissal?.cancel()
        withAnimation(Theme.messageAnimation) { connection = state }
    }

    func suspendAutomaticRequests() {
        cancelStream()
        linkGrace?.cancel(); linkGrace = nil
        if connection != .hidden { setConnection(.hidden) }
        cancelAutomaticRetry()
        userTypingTask?.cancel()
    }

    /// Resends one failed message at a time, oldest first, so a queue keeps its order and never races itself.
    func retryFailedAutomatically() {
        // Never while an earlier message is still in flight: it would be overtaken.
        guard canSend, !verificationRequired, isWatched, automaticRetry == nil, let session, session.halt == nil,
              let start = messages.firstIndex(where: { retriesAutomatically($0) && sends[$0.id] == nil }),
              !messages[..<start].contains(where: { sends[$0.id] != nil }) else { return }
        let messageId = messages[start].id
        let retryId = UUID()
        let task = Task { [weak self] in
            while let self, !Task.isCancelled, self.canSend, !self.verificationRequired, session.halt == nil,
                  let index = self.messages.firstIndex(where: { $0.id == messageId }),
                  self.retriesAutomatically(self.messages[index]) {
                let cooldown = self.cooldown(for: self.messages[index])
                if cooldown?.automatic == false {
                    // A longer wait arrived meanwhile: sending later is the person's decision.
                    self.messages[index].awaitsManualRetry = true
                    self.saveMessages()
                    break
                }
                let waits: [Duration?] = [session.retries[messageId]?.delay,
                                          cooldown.map { .seconds(max(0, $0.until.timeIntervalSince(session.cooldowns.now()))) }]
                if let delay = waits.compactMap({ $0 }).max(), delay > .zero {
                    do { try await Task.sleep(for: delay) } catch { break }
                    continue
                }
                if let earlier = self.messages[..<index].lazy.compactMap({ self.sends[$0.id] }).first {
                    await earlier.value
                    continue
                }
                guard self.sends[messageId] == nil else { break }
                withAnimation(Theme.messageAnimation) { self.messages[index].status = .sending }
                self.submit(messageId)
                await self.sends[messageId]?.value
            }
            guard let self, self.automaticRetry?.id == retryId else { return }
            self.automaticRetry = nil
            self.retryFailedAutomatically()
        }
        automaticRetry = AutomaticRetry(messageId: messageId, id: retryId, task: task)
    }
}
