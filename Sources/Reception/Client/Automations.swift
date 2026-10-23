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
    private var running: Set<String> = []
    private var checkingSubscriptions = false
    private var subscriptionsCheckedAt: ContinuousClock.Instant?
    private var openedChatAt: ContinuousClock.Instant?

    static func accepts(_ event: String) -> Bool {
        event.range(of: "^[A-Za-z0-9_.-]{1,64}$", options: .regularExpression) != nil
    }

    /// What became of an event: no enabled automation listens for it, send it again later, it was handled, with
    /// whether the service says an automation that opens the chat reached this device, or its automation opened the chat.
    private enum Delivery: Equatable { case unheard, retry, handled(openChat: Bool), openedChat }

    func track(_ event: String, opensChat: Bool, session: DeviceSession) {
        let start = ContinuousClock.now
        let presentation = Reception.shared.presentationRevision
        Task {
            let delivery = await deliver(event, session: session, start: start, presentation: presentation)
            // The service decides: the chat opens again only for people an enabled automation that opens it reached,
            // so nobody it excludes, delays or reaches with a badge or push sees an empty chat.
            guard opensChat, delivery == .handled(openChat: true), session.halt == nil,
                  canOpenChat(start: start, presentation: presentation) else { return }
            Reception.shared.openChat()
        }
    }

    /// Sends `event` when an automation listens for it and opens the chat if the service sent a message that opens it.
    /// Retry only when the event should be sent again later: the request failed, or the same event is already on its way.
    private func deliver(_ event: String, session: DeviceSession, start: ContinuousClock.Instant, presentation: Int) async -> Delivery {
        guard session.halt == nil else { return .retry }
        guard await listens(to: event, session: session) else { return .unheard }
        guard running.insert(event).inserted else { return .retry }
        defer { running.remove(event) }
        guard let result = await send(event, session: session) else { return .retry }
        guard session === Reception.shared.session else { return .handled(openChat: false) }
        if result.sent { return received(result, event: event, session: session, start: start, presentation: presentation) }
        if result.scheduled == true { scheduled(event, session: session) }
        return .handled(openChat: result.openChat)
    }

    /// A message that waits for its time arrives later, so the chat watches for it from now on, as after a send.
    private func scheduled(_ event: String, session: DeviceSession) {
        Log.debug("Automation message scheduled for \(event)")
        session.store.hasStartedChat = true
    }

    private func received(_ result: Sent, event: String, session: DeviceSession, start: ContinuousClock.Instant, presentation: Int) -> Delivery {
        Log.debug("Automation message received for \(event)")
        session.store.hasStartedChat = true
        Reception.shared.refreshUnread()
        guard result.openChat, canOpenChat(start: start, presentation: presentation) else { return .handled(openChat: result.openChat) }
        openedChatAt = .now
        Reception.shared.openChat()
        return .openedChat
    }

    /// Only soon after `track`, while the app shows the same screens in front and the chat is closed.
    private func canOpenChat(start: ContinuousClock.Instant, presentation: Int) -> Bool {
        ContinuousClock.now - start < openWindow && presentation == Reception.shared.presentationRevision
            && UIApplication.shared.applicationState == .active && !Reception.shared.isChatOpen
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
                    let delivery = await deliver(event, session: session, start: .now, presentation: Reception.shared.presentationRevision)
                    guard delivery != .retry else { continue }
                    Log.debug("Subscription change reported as \(event)")
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
        struct Response: Decodable { let events: [String] }
        do {
            let response: Response = try await session.api.request("automations")
            listened = Listened(appId: appId, events: Set(response.events), until: .now + .seconds(300))
        } catch {
            Log.debug("Automations unavailable, events are not sent for a minute")
            listened = Listened(appId: appId, events: [], until: .now + .seconds(60))
        }
        return listened?.events.isDisjoint(with: events) == false
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
