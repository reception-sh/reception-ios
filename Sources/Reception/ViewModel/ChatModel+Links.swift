import SwiftUI

extension ChatModel {
    /// The host's handler and links into the host app run after the chat closed, so the host can switch tabs or
    /// present freely. Other links open with the chat left open: web pages in Safari over it, the rest through the
    /// system, like review cards.
    func openLink(_ url: URL, messageId: String) {
        guard !isClosingForLink else { return }
        Reception.shared.onEvent?(.linkOpened)
        if let handler = Reception.shared.onLink {
            closeForLink { [self] in
                if handler(url) { recordLinkOutcome(.handled, messageId: messageId) }
                else { openOutsideChat(url, messageId: messageId) }
            }
        } else if isHostLink(url) {
            closeForLink { [self] in openExternally(url, messageId: messageId) }
        } else {
            openOutsideChat(url, messageId: messageId)
        }
    }

    /// A tapped web address in message text: Safari over the chat, or the system's default handling. No receipt.
    func openTextLink(_ url: URL) -> OpenURLAction.Result {
        opensInSafari(url) && presentWebLink(url) ? .handled : .systemAction
    }

    /// Whether a link card leads back into the host app.
    func isHostLink(_ url: URL) -> Bool { LinkPolicy.main.isHostScheme(url) }

    private func opensInSafari(_ url: URL) -> Bool {
        Reception.shared.opensWebLinksInApp && LinkPolicy.isWebLink(url)
    }

    private func closeForLink(then next: @escaping () -> Void) {
        isClosingForLink = true
        closePresentedChat { [self] in
            isClosingForLink = false
            next()
        }
    }

    /// Without a screen to present Safari from, the system opens the web page instead.
    private func openOutsideChat(_ url: URL, messageId: String) {
        if opensInSafari(url) && presentWebLink(url) { recordLinkOutcome(.opened, messageId: messageId) }
        else { openExternally(url, messageId: messageId) }
    }

    private func openExternally(_ url: URL, messageId: String) {
        openExternal(url) { [self] accepted in recordLinkOutcome(accepted ? .opened : .failed, messageId: messageId) }
    }

    private func recordLinkOutcome(_ outcome: ActionOutcome, messageId: String) {
        if current { session?.recordActionClick(messageId, outcome: outcome) }
    }
}
