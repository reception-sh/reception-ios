import SwiftUI
import Observation
import Network

@MainActor @Observable
internal final class ChatModel {
    var messages: [Message] = []
    /// Reply authors by ID. Each opening replaces it, so photo URLs stay fresh; kept in memory only.
    var team: [String: TeamMember] = [:] {
        didSet { teamPhotos.update(Reception.resolvedAppearance.showsTeamPhotos ? team : [:]) }
    }
    let teamPhotos = TeamPhotos()
    var sendingDisabled = false
    /// The app accepts only verified users and this session is not one; kept in memory only.
    var verificationRequired = false
    var sendingPermissionRevision = 0
    let composer: ComposerModel
    var connection: ConnectionState = .hidden
    var pathMonitor: NWPathMonitor?
    var pathTask: Task<Void, Never>?
    var connectionDismissal: Task<Void, Never>?
    var automaticRetry: AutomaticRetry?
    var limitReleaseRetries = Set<String>()
    var isVisible = false
    var isLoading = false
    var uploadProgress: Double?
    let session: DeviceSession?
    var polling: Task<Void, Never>?
    var streamID: UUID?
    var streamConnected = false
    var pathSatisfied: Bool?
    var linkGrace: Task<Void, Never>?
    var isTyping = false
    var typingDismissal: Task<Void, Never>?
    var userTypingTask: Task<Void, Never>?
    var userTypingIdle: Task<Void, Never>?
    var userIsTyping = false
    var lastUserTyping = Date.distantPast
    var sends: [String: Task<Void, Never>] = [:]
    var pendingTimers: [String: Task<Void, Never>] = [:]
    var loading = false
    private(set) var isChatActive = false
    var maxSeq: Int64 = 0
    var readCursor: ReadCursor?
    var reloadTask: Task<Void, Never>?
    var pollDeferred = false
    var canSend: Bool { current && (!sendingDisabled || session?.halt == .blocked) }
    var current: Bool { session != nil && session === Reception.shared.session && session?.invalidated == false }

    convenience init() { self.init(session: Reception.shared.session) }

    init(session: DeviceSession?) {
        self.session = session
        composer = ComposerModel(store: session?.store)
        messages = session?.store.chatCache.load() ?? []
        // Interrupted submissions use the same serial recovery path, after history reconciliation.
        for index in messages.indices where messages[index].seq == nil && messages[index].status == .sending {
            messages[index].status = .failed
            messages[index].retryAfterTransientFailure = true
        }
        composer.onTextChange = { [weak self] text in self?.sendTyping(!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
    }

    func canOpenPaywall(_ message: Message) -> Bool {
        message.kind == "PAYWALL" && Reception.shared.onPaywall != nil &&
            Reception.shared.availablePaywalls.contains { $0.id == message.paywallId }
    }

    func openPaywall(_ message: Message) {
        guard canOpenPaywall(message), let id = message.paywallId,
              let handler = Reception.shared.onPaywall else { return }
        if current { session?.recordActionClick(message.id) }
        Reception.shared.onEvent?(.paywallOpened)
        handler(id)
    }

    func openReview(_ url: URL, messageId: String, using openURL: OpenURLAction) {
        if current { session?.recordActionClick(messageId) }
        Reception.shared.onEvent?(.reviewOpened)
        openURL(url)
    }

    func saveMessages() { if current { session?.store.chatCache.save(messages) } }

    func startPolling() {
        isChatActive = true
        guard session?.store.hasStartedChat == true else { return }
        startStream()
        for message in messages where message.status == .sending { submit(message.id) }
        startMonitoring()
        retryFailedAutomatically()
    }
    func stopPolling() {
        isChatActive = false
        reloadTask?.cancel(); reloadTask = nil
        if current { Reception.shared.invalidateRead() }
        sendTyping(false)
        cancelStream()
        setTyping(false)
        linkGrace?.cancel(); linkGrace = nil
        pathTask?.cancel(); pathTask = nil
        pathMonitor?.cancel(); pathMonitor = nil
        cancelAutomaticRetry()
        deferCooldownRetries()
        connectionDismissal?.cancel()
        if connection != .offline { connection = .hidden }
    }

    func poll() async {
        guard let session, current, isChatActive, !Task.isCancelled,
              UIApplication.shared.applicationState == .active,
              session.store.hasStartedChat, session.halt == nil, session.retries["poll"]?.stopped != true, !loading else { return }
        // A request wait must not hold the stream reader; cooldownsChanged polls once it ends.
        guard session.cooldowns.blocking([.requests]) == nil else { pollDeferred = true; return }
        loading = true
        defer { loading = false }
        do {
            if let delay = session.retries["poll"]?.delay { try await Task.sleep(for: delay) }
            // Pages follow while the service reports more; each one is merged and read like a single poll.
            var hasMore = true
            while hasMore {
                guard current, isChatActive, !Task.isCancelled,
                      UIApplication.shared.applicationState == .active else { return }
                let after = maxSeq
                let generation = Reception.shared.readGeneration
                let permissionRevision = sendingPermissionRevision
                let response: MessagesResponse = try await session.api.request("conversation/messages?after=\(after)", authenticated: true)
                guard current, isChatActive, !Task.isCancelled,
                      UIApplication.shared.applicationState == .active else { return }
                guard generation == Reception.shared.readGeneration else { reloadAfterStaleGet(); return }
                if let device = response.device { updateSendingPermission(device, revision: permissionRevision) }
                team.merge((response.team ?? []).map { ($0.id, $0) }) { _, latest in latest }
                withAnimation(Theme.messageAnimation) { merge(response.messages) }
                try await markRead(target: processedReadTarget(
                    conversationId: response.conversation?.id, hasConversation: response.conversation != nil,
                    boundedRead: response.boundedRead, messages: response.messages))
                hasMore = response.hasMore == true
                // A page that does not advance the cursor would repeat forever.
                if hasMore && maxSeq <= after { throw ReceptionAPIError(code: "invalid_response", status: 200) }
            }
            session.retries["poll"] = nil
        } catch {
            if !Task.isCancelled, session.halt == nil { session.retries["poll", default: RetryState()].failed(error) }
            report(error)
        }
    }
    func refreshUnread(updateDevice: Bool = false, probe: Bool = false) async {
        guard let session, current, session.store.hasStartedChat,
              session.halt == nil || probe, session.isRegistered,
              probe || session.retries["unread"]?.stopped != true else { return }
        defer { if current, !Task.isCancelled { Reception.shared.unreadMonitor.reschedule() } }
        do {
            if !probe, let delay = session.retries["unread"]?.delay { try await Task.sleep(for: delay) }
            if updateDevice && !probe { try await session.update() }
            struct Response: Decodable {
                let hasConversation: Bool
                let unreadCount: Int
                let status: String?
                let lastMessageAt: Date?
                let push: Bool?
                let unreadPolling: [UnreadStage]?
            }
            let generation = Reception.shared.readGeneration
            let response: Response = try await RequestContext.$probe.withValue(probe ? RequestProbe() : nil) {
                try await session.api.request("conversation/unread", authenticated: true)
            }
            session.retries["unread"] = nil
            if probe { sendingDisabled = false }
            guard current, !Task.isCancelled else { return }
            session.store.hasConversation = response.hasConversation
            session.store.conversationStatus = response.status
            session.store.lastMessageAt = response.lastMessageAt
            session.store.pushActive = response.push
            session.store.unreadPolling = response.unreadPolling
            // A read invalidates older badge responses, even after the chat closes.
            if generation == Reception.shared.readGeneration, !isVisible {
                Reception.shared.setUnread(response.unreadCount)
            }
            Log.debug("Unread refresh, \(response.unreadCount) unread")
        } catch {
            if let error = error as? ReceptionAPIError, error.code != "cancelled", error.code != "session_halted", !error.isCooldown {
                if probe && error.status == 403 && error.code == "blocked" {
                    Log.debug("Request skipped, session halted")
                } else {
                    Log.error("Unread refresh failed, HTTP \(error.status) \(error.code)")
                }
            }
            if session.halt == nil { session.retries["unread", default: RetryState()].failed(error) }
            _ = handleReset(error)
        }
    }
    func merge(_ incoming: [Message], advancesCursor: Bool = true) {
        for message in incoming {
            if let index = messages.firstIndex(where: { existing in
                (message.seq != nil && existing.seq == message.seq) ||
                message.clientId.map { $0 == existing.id || $0 == existing.clientId } == true
            }) {
                var updated = message
                updated.id = messages[index].id
                if !updated.hasConfirmedAttachments {
                    updated.images = messages[index].images
                    updated.attachmentIds = messages[index].attachmentIds
                }
                updated.status = .sent
                clearPending(updated.id)
                messages[index] = updated
            } else {
                messages.append(message)
                if message.sender == "AGENT" { setTyping(false) }
            }
        }
        messages.sort {
            if let left = $0.seq, let right = $1.seq { return left < right }
            return $0.createdAt < $1.createdAt
        }
        if advancesCursor {
            maxSeq = max(maxSeq, incoming.compactMap(\.seq).max() ?? 0)
            session?.store.cursor = maxSeq
        }
        if !incoming.isEmpty { saveMessages() }
    }
    @discardableResult
    func handleReset(_ error: Error) -> Bool {
        guard current, let error = error as? ReceptionAPIError else { return false }
        session?.recordFailure(error)
        guard error.status == 409, error.code == "chat_reset", let revision = error.resetRevision, revision >= 0 else { return false }
        Log.info("Chat reset by the team, local history cleared, revision \(revision)")
        Reception.shared.resetChat(revision: revision)
        return true
    }

}
