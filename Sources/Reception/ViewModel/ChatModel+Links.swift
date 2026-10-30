import SwiftUI

extension ChatModel {
    /// Screens and links into the host app open after the chat closed, so the host can switch tabs or present freely.
    /// Other links open with the chat left open: web pages in the installed app that claims them, else in Safari over the
    /// chat; the rest through the system, like review cards.
    func openLink(_ url: URL, messageId: String) {
        guard !isClosingForLink else { return }
        Reception.shared.onEvent?(.linkOpened)
        if let target = ScreenLink(url) {
            closeForLink { [self] in openScreen(target, messageId: messageId) }
        } else if isHostLink(url) {
            closeForLink { [self] in openExternally(url, messageId: messageId) }
        } else {
            openOutsideChat(url, messageId: messageId)
        }
    }

    /// A tapped web address in message text: the claiming app or Safari over the chat, or the system's default
    /// handling. No receipt.
    func openTextLink(_ url: URL) -> OpenURLAction.Result {
        guard opensInSafari(url) else { return .systemAction }
        openWebLink(url) { [self] presented in if !presented { openExternal(url) { _ in } } }
        return .handled
    }

    /// Whether a link card leads back into the host app.
    func isHostLink(_ url: URL) -> Bool { ScreenLink(url) != nil || LinkPolicy.main.isHostScheme(url) }

    /// Runs the host's screen for a screen link. The service only sends one the device reported; a screen the app no
    /// longer lists, or one missing its value, counts as failed.
    private func openScreen(_ target: ScreenLink, messageId: String) {
        let screen = ScreenLink.usable(Reception.shared.screens).first { $0.id == target.id }
        guard let screen, screen.valueName == nil || target.value != nil else {
            Log.info("No screen \(target.id) for this link")
            return recordLinkOutcome(.failed, messageId: messageId)
        }
        screen.open(target.value)
        recordLinkOutcome(.handled, messageId: messageId)
    }

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
        guard opensInSafari(url) else { return openExternally(url, messageId: messageId) }
        openWebLink(url) { [self] opened in
            if opened { recordLinkOutcome(.opened, messageId: messageId) } else { openExternally(url, messageId: messageId) }
        }
    }

    /// An installed app that claims the web link opens it, as in Messages and Mail; otherwise Safari over the chat.
    /// Reports false when neither happened.
    private func openWebLink(_ url: URL, then done: @escaping @MainActor (Bool) -> Void) {
        openInClaimingApp(url) { [self] claimed in done(claimed || presentWebLink(url)) }
    }

    private func openExternally(_ url: URL, messageId: String) {
        openExternal(url) { [self] accepted in recordLinkOutcome(accepted ? .opened : .failed, messageId: messageId) }
    }

    private func recordLinkOutcome(_ outcome: ActionOutcome, messageId: String) {
        if current { session?.recordActionClick(messageId, outcome: outcome) }
    }
}
