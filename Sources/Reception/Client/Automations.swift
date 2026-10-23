import UIKit

/// Sends tracked events that a dashboard automation listens for, and opens the chat when the service sent its message.
/// Every failure ends quietly: an automation is optional and must never disturb the host app.
@MainActor
internal final class Automations {
    private struct Listened { let appId: String; let events: Set<String>; let until: ContinuousClock.Instant }
    private struct Sent: Decodable { let sent: Bool; let scheduled: Bool?; let openChat: Bool }

    /// The chat opens only this soon after `track`, so a slow response never surprises the user later.
    private let openWindow = Duration.seconds(5)
    private var listened: Listened?
    private var listing: (appId: String, task: Task<Listened, Never>)?
    private var running: Set<String> = []
    private var checkingSubscriptions = false
    private var subscriptionsCheckedAt: ContinuousClock.Instant?
    private var openedChatAt: ContinuousClock.Instant?

    static func accepts(_ event: String) -> Bool {
        event.range(of: "^[A-Za-z0-9_.-]{1,64}$", options: .regularExpression) != nil
    }

    /// What became of an event: no enabled automation listens for it, send it again later, its message was just
    /// sent, or it was handled otherwise; both with whether the service says a chat-opening automation reached this device.
    private enum Delivery: Equatable { case unheard, retry, received(openChat: Bool), handled(openChat: Bool) }

    func track(_ event: String, opensChat: Bool, session: DeviceSession) {
        let start = ContinuousClock.now
        let presentation = Reception.shared.presentationRevision
        Task {
            let delivery = await deliver(event, session: session)
            guard session.halt == nil else { return }
            switch delivery {
            case .received(openChat: true):
                await openChatWhenSettled(start: start, presentation: presentation, arriving: true)
            // The service decides: the chat opens again only for people an enabled automation that opens it reached,
            // so nobody it excludes, delays or reaches with a badge or push sees an empty chat.
            case .handled(openChat: true) where opensChat:
                await openChatWhenSettled(start: start, presentation: presentation, arriving: false)
            default:
                return
            }
        }
    }

    /// Sends `event` when an automation listens for it and opens the chat if the service sent a message that opens it.
    /// Retry only when the event should be sent again later: the request failed, or the same event is already on its way.
    private func deliver(_ event: String, session: DeviceSession) async -> Delivery {
        guard session.halt == nil else { return .retry }
        guard await listens(to: event, session: session) else { return .unheard }
        guard running.insert(event).inserted else { return .retry }
        defer { running.remove(event) }
        guard let result = await send(event, session: session) else { return .retry }
        guard session === Reception.shared.session else { return .handled(openChat: false) }
        if result.sent { return received(result, event: event, session: session) }
        if result.scheduled == true { scheduled(event, session: session) }
        return .handled(openChat: result.openChat)
    }

    /// A message that waits for its time arrives later, so the chat watches for it from now on, as after a send.
    private func scheduled(_ event: String, session: DeviceSession) {
        Log.debug("Automation message scheduled for \(event)")
        session.store.hasStartedChat = true
    }

    private func received(_ result: Sent, event: String, session: DeviceSession) -> Delivery {
        Log.debug("Automation message received for \(event)")
        session.store.hasStartedChat = true
        Reception.shared.refreshUnread()
        return .received(openChat: result.openChat)
    }

    /// Opens the chat as soon as the app is active and no screen in front is still opening or closing, if that comes
    /// within the window after the event; later, it would surprise the user. A cancelled purchase is reported while
    /// the App Store sheet is still closing, and a closed paywall often comes straight back, so neither moment is
    /// missed. The chat stays closed if the person logged out meanwhile or the chat is already open.
    private func openChatWhenSettled(start: ContinuousClock.Instant, presentation: Int, arriving: Bool) async {
        while ContinuousClock.now - start < openWindow {
            guard presentation == Reception.shared.presentationRevision, !Reception.shared.isChatOpen else { return }
            if Reception.shared.presenter.isSettled {
                if arriving { openedChatAt = .now }
                if Reception.shared.presenter.present() { return }
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        Log.debug("Chat not opened, the app or its screens did not settle in time")
    }

    /// Whether an automation opened the chat a moment ago, so its message can arrive like a reply. Answers once.
    func takeOpenedChat() -> Bool {
        defer { openedChatAt = nil }
        guard let openedChatAt else { return false }
        return ContinuousClock.now - openedChatAt < openWindow
    }

    /// Reports a cancelled trial or subscription, a failed payment or an expired subscription the App Store shows
    /// since the last check. Runs when the app opens, at most once a minute, and only while an automation listens.
    func checkSubscriptions(session: DeviceSession) {
        if let subscriptionsCheckedAt, ContinuousClock.now - subscriptionsCheckedAt < .seconds(60) { return }
        guard session.halt == nil, !checkingSubscriptions else { return }
        checkingSubscriptions = true
        subscriptionsCheckedAt = .now
        Task {
            defer { checkingSubscriptions = false }
            guard await listens(toAnyOf: StoreSubscriptions.events, session: session) else { return }
            var known = session.store.subscriptionStates
            for (group, state) in await StoreSubscriptions.current() {
                if let event = StoreSubscriptions.event(from: known[group], to: state) {
                    // An undelivered change keeps the old state, so the next check reports it again.
                    let start = ContinuousClock.now
                    let presentation = Reception.shared.presentationRevision
                    let delivery = await deliver(event, session: session)
                    guard delivery != .retry else { continue }
                    Log.debug("Subscription change reported as \(event)")
                    if delivery == .received(openChat: true), session.halt == nil {
                        await openChatWhenSettled(start: start, presentation: presentation, arriving: true)
                    }
                }
                known[group] = state
            }
            if session === Reception.shared.session { session.store.subscriptionStates = known }
        }
    }

    /// A purchase must reach the service before a delayed automation offers a discount, so a registered device sends
    /// a change of paid access or `subscription_status` at once instead of with its next update. It changes rarely,
    /// so this never loops.
    func subscriptionChanged(session: DeviceSession) {
        guard session.halt == nil, session.isRegistered else { return }
        Task {
            do { try await RequestContext.$automation.withValue(true) { try await session.update() } }
            catch { Log.debug("Subscription change not delivered, it follows with the next update") }
        }
    }

    /// Whether an enabled automation listens for `event`. Other events never leave the device.
    private func listens(to event: String, session: DeviceSession) async -> Bool {
        await listens(toAnyOf: [event], session: session)
    }

    private func listens(toAnyOf events: Set<String>, session: DeviceSession) async -> Bool {
        let appId = session.api.appId
        if let listened, listened.appId == appId, ContinuousClock.now < listened.until { return !listened.events.isDisjoint(with: events) }
        // Events often arrive together, like a closed paywall and the purchase it ended; one request answers them all.
        let task: Task<Listened, Never>
        if let listing, listing.appId == appId {
            task = listing.task
        } else {
            task = Task { await Self.fetchListened(appId: appId, api: session.api) }
            listing = (appId, task)
        }
        let result = await task.value
        if listing?.task == task { listing = nil }
        listened = result
        return !result.events.isDisjoint(with: events)
    }

    private static func fetchListened(appId: String, api: ReceptionAPI) async -> Listened {
        struct Response: Decodable { let events: [String] }
        do {
            let response: Response = try await api.request("automations")
            return Listened(appId: appId, events: Set(response.events), until: .now + .seconds(300))
        } catch {
            Log.debug("Automations unavailable, events are not sent for a minute")
            return Listened(appId: appId, events: [], until: .now + .seconds(60))
        }
    }

    private func send(_ event: String, session: DeviceSession) async -> Sent? {
        do {
            return try await RequestContext.$automation.withValue(true) {
                // The service decides with current paid access, metadata and paywalls, so a registered device syncs them first.
                await Reception.shared.paidAccess.refreshNow()
                if session.isRegistered { try await session.update() }
                return try await session.api.request("automations/events", method: "POST", authenticated: true,
                    body: ReceptionAPI.encode(["event": event]))
            }
        } catch {
            Log.debug("Automation event not delivered")
            return nil
        }
    }
}
