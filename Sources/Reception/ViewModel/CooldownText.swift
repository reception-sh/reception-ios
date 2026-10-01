import Foundation

/// Wait texts in the chat language. The expiry only permits another attempt, so no text promises delivery.
@MainActor
internal enum CooldownText {
    static func notice(_ cooldown: ServerCooldowns.Cooldown, now: Date) -> String {
        let wait = relative(until: cooldown.until, now: now)
        return switch cooldown.scope {
        case .messages: Theme.string("Message limit reached. You can send again \(wait).")
        case .uploads: Theme.string("Photos can be sent again \(wait). You can still send text.")
        case .requests: Theme.string("Too many attempts. Try again \(wait).")
        case .session, .stream: Theme.string("Can't connect right now. Try again \(wait).")
        }
    }

    static func resend(until deadline: Date, now: Date) -> String {
        Theme.string("Sending again \(relative(until: deadline, now: now))")
    }

    /// "in 8 seconds", "in 13 minutes", "in 2 hours": rounded up in the largest unit, so the wait is never
    /// understated. The formatter supplies each language's own grammar for the phrase.
    static func relative(until deadline: Date, now: Date) -> String {
        let seconds = max(1, deadline.timeIntervalSince(now).rounded(.up))
        let unit: TimeInterval = seconds < 60 ? 1 : seconds < 3600 ? 60 : 3600
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = ReceptionLocalization.locale
        formatter.unitsStyle = .full
        formatter.formattingContext = .middleOfSentence
        return formatter.localizedString(for: now.addingTimeInterval((seconds / unit).rounded(.up) * unit), relativeTo: now)
    }
}
