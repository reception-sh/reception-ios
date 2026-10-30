import UserNotifications

/// What the dashboard lets the notification card promise.
internal enum PushPrompt: String {
    case replies, offers
}

internal enum PushPromptSlot: Equatable {
    case card(PushPrompt), status, none
}

internal enum PushPromptDecision {
    /// The slot under the person's latest message: the card asks once while iOS has not asked yet,
    /// the status line confirms push once the service can reach this device. Both step aside while that message
    /// failed or this device can't write, since neither can promise a reply then; a message still sending keeps
    /// them in place, so they don't flicker with every send.
    static func resolve(prompt: PushPrompt?, authorization: UNAuthorizationStatus?, declined: Bool, answered: Bool,
                        lastSender: String?, lastFailed: Bool, canWrite: Bool, pushActive: Bool?,
                        hidesStatus: Bool = false) -> PushPromptSlot {
        guard lastSender == "USER", !lastFailed, canWrite else { return .none }
        if let prompt, authorization == .notDetermined, !declined, !answered { return .card(prompt) }
        if !hidesStatus, let authorization, PushAuthorization.allowsRegistration(authorization), pushActive == true { return .status }
        return .none
    }
}
