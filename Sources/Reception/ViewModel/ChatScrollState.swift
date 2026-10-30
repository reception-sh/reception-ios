import Foundation

/// Decides when the chat follows new content and when it offers the jump-to-latest control. A reader at the newest
/// message keeps following; a reader further up keeps their place and sees how many replies arrived below.
internal struct ChatScrollState: Equatable {
    struct Entry: Equatable {
        let id: String
        let sender: String
    }

    static let userSender = "USER"

    /// Whether the newest message row is on screen. It stays set while new rows lay out below it, so the chat keeps
    /// following until that row has actually left the screen.
    private(set) var showsNewest = true
    /// Team replies that arrived below while the reader was further up, by message ID so a reload never counts twice.
    private(set) var unseenIds: Set<String> = []
    private var knownIds: Set<String> = []
    private var visibleNewestId: String?

    var unseenCount: Int { unseenIds.count }
    /// Layout changes, the typing indicator and replies only scroll a reader who is at the newest message.
    var followsNewest: Bool { showsNewest }
    var showsJumpControl: Bool { !unseenIds.isEmpty }

    /// Returns whether to scroll to the newest message after the history changed. The reader's own message always
    /// scrolls; team replies only follow a reader at the newest message and are counted otherwise.
    mutating func messagesChanged(_ messages: [Entry]) -> Bool {
        let previous = knownIds
        knownIds = Set(messages.map(\.id))
        unseenIds.formIntersection(knownIds)
        // A first load, or a history that shares nothing with the previous one, starts at the end.
        guard let lastKnown = messages.lastIndex(where: { previous.contains($0.id) }) else {
            jumpedToNewest()
            return !messages.isEmpty
        }
        // Only messages below everything already shown count as new; a reload that fills in older ones doesn't.
        let arrivals = messages[(lastKnown + 1)...].filter { !previous.contains($0.id) }
        if arrivals.contains(where: { $0.sender == Self.userSender }) {
            jumpedToNewest()
            return true
        }
        guard !arrivals.isEmpty, !showsNewest else { return !arrivals.isEmpty }
        unseenIds.formUnion(arrivals.map(\.id))
        return false
    }

    /// The newest row moved on or off screen. A row that was never on screen can't leave it, so a reply laid out
    /// below a reader at the newest message doesn't stop the chat from following it there.
    mutating func newest(_ id: String, isVisible: Bool) {
        if isVisible {
            visibleNewestId = id
            showsNewest = true
            unseenIds.removeAll()
        } else if visibleNewestId == id {
            visibleNewestId = nil
            showsNewest = false
        }
    }

    /// The reader tapped the control or sent a message; both end at the newest message.
    mutating func jumpedToNewest() {
        showsNewest = true
        unseenIds.removeAll()
    }

    /// The unread label, such as "3 new messages", capped at "99+ new messages" so the control stays compact. `format`
    /// returns the localized plural for a count; nil without unseen replies.
    static func unreadText(for count: Int, locale: Locale, format: (Int) -> String) -> String? {
        guard count > 0 else { return nil }
        let limit = Theme.jumpToLatestCountLimit
        guard count > limit else { return format(count) }
        let text = format(limit)
        let number = limit.formatted(.number.locale(locale))
        guard let range = text.range(of: number) else { return text }
        return text.replacingCharacters(in: range, with: number + "+")
    }
}
