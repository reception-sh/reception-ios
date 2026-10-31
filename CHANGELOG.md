# Changelog

All notable changes to the Reception iOS SDK are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project follows [Semantic Versioning](https://semver.org/).

## [1.7.0] — 2026-10-31

### Added

- A small card in the chat asks for notification permission after the person's message, only when enabled in the dashboard and only while iOS has not asked yet. Continue shows the system prompt and registers for push when allowed; No thanks hides the card on this device for good, also after logout.
- A one-line status under the person's latest message confirms that they'll get a notification when the team replies, once push works for the device. Hide it with `Reception.shared.appearance.hidesPushStatus` or in the dashboard.
- Link cards: a message from your team can carry a button that opens a link, such as a website, another app's link, an App Store page or offer-code link, an email address, a phone number or your app's page in iOS Settings, with no code in your app. Links to your app's own URL schemes (from `CFBundleURLTypes` in `Info.plist`) close the chat and then open, so your app's URL handler receives them; other links open with the chat left open. A card whose URL is missing or not allowed shows as plain text.
- `Reception.shared.screens` lists the places in your app that link cards can open, such as tabs, screens, sheets or the paywall, each a `ReceptionScreen` with an ID and the code that opens it; `ReceptionScreen("order", value: "Order number") { number in … }` takes a value from the link. No URL scheme or router is needed. Device registration and updates report the screen IDs (`screens`), so the dashboard offers them by name and sends a screen link only to app versions that list the screen. A screen link closes the chat, then runs the screen's code.
- `ReceptionEvent.linkOpened` is emitted when someone taps a link card. Apps with an exhaustive `switch` over `ReceptionEvent` need to add this case.
- Web links from link cards and message text open in the installed app that claims them (for example WhatsApp for `wa.me`, YouTube, Instagram), as from Messages or Mail; otherwise in an in-app Safari sheet over the chat, so people return to the conversation with Done. App Store links still open the App Store. Set `Reception.shared.opensWebLinksInApp = false` to hand web links to the system (Safari or another app's universal link) instead.
- Device registration and updates report `capabilities` (`linkCards`, `screens`): what this SDK can show, so the server sends link cards and screen links to it by what it reports, not by its version number.
- Device registration and updates report the original transaction IDs of the person's App Store purchases (`transactionIds`), so App Store Server Notifications connected in the dashboard reach the right person. Nothing is needed in the app.
- A link card's receipt reports whether a screen opened, the system opened the link, or it could not be opened, so the dashboard can show a failed tap.
- The chat keeps your place when you scroll up: opening a link, returning from another app or a new reply no longer jumps to the bottom. Replies that arrive while you're scrolled up show a "3 new messages" button above the composer that scrolls down to them.

### Changed

- The chat sheet can be closed while the keyboard is open: drag down from the grabber or the title bar. A drag over the messages then puts the keyboard away instead. With the keyboard closed, a drag anywhere closes the sheet, as before. Before, no drag could close the sheet while the keyboard was up.

### Fixed

- `ReceptionChatView()` stays open when pushed through a navigation path (`NavigationStack(path:)` with `navigationDestination(for:)`). Before, the chat closed right after the push, and the app could crash on the next change of that path.
- The German Retry button reads “Erneut versuchen”, and deleting the person's data also clears the stored subscription states.

## [1.6.0] — 2026-10-24

### Changed

- The device registers with Reception when the app launches or returns to the foreground, not only when the person first writes, so every install appears in the dashboard's Users page and the team can start a conversation. Nothing is sent before `configure`; registration carries the same device details as before.
- A registered device checks for unread messages on launch and foreground even before the person has written, and a tapped notification counts as a conversation. A conversation the team started therefore loads in the chat, polls and badges like one the person started. Before, the app ignored the team's message until the person wrote first.

### Fixed

- Swiping down over the messages while typing now dismisses the keyboard instead of the whole chat sheet; the sheet can be swiped away again once the keyboard is gone.
- On iOS 26 the messages fade out under the chat title instead of being cut off by a hard band, and messages show through the glass composer all the way to the bottom of the sheet.
- Links in messages are tappable, a long press on a bubble offers Copy, a reply that arrives while the chat is open gives a light haptic, and bubbles and the send button animate with springs.
- The chat moves like Messages: on iOS 18 and later the newest message stays pinned above the composer while the keyboard opens and closes, and new messages scroll in with an animation instead of a jump. iOS 17 scrolls into place once the keyboard has settled.
- Device preferences (paywalls, language, badge setting) synchronize for a registered device that has not written yet.

## [1.5.0] — 2026-10-23

### Added

- `Reception.shared.track(_:opensChat:)` reports app events, such as a closed paywall, for automations set up in the dashboard. An automation's message arrives in the chat once; with `opensChat: true` the chat opens when the message is sent and again at later events for people who received it.
- While an automation listens for them, the SDK reports `trial_cancelled`, `trial_expired`, `subscription_cancelled`, `billing_issue` and `subscription_expired` from the App Store when the app becomes active.
- Device registration and updates report whether the person has paid access in the App Store.
- The team's typing indicator shows briefly before an automation's message appears in a chat it opened.

### Fixed

- The chat no longer opens on a screen that is being dismissed, where it would close with that screen.
- An automation opens the chat once the app is active again and the screen in front has finished opening or closing, as long as that comes within five seconds of the event. A cancelled purchase is reported while the App Store sheet is still closing, and a closed paywall often comes straight back; before, the chat stayed closed in both cases and the message waited unread.

## [1.4.1] — 2026-10-22

### Fixed

- The live connection no longer stops for good after eight drops over the life of a session. A stream that stayed up for ten seconds now starts a fresh backoff when it drops, eight failures in a row only slow retries to once a minute while the chat stays open, and reopening the chat, sending a message or the network coming back retries at once. Before, the chat could show “Connecting” without trying again until the app went to the background and returned.

## [1.4.0] — 2026-10-22

### Added

- `ReceptionPaywall` takes an optional `source` (`.revenueCat`, `.superwall`, `.adapty`, `.app`, or any lowercase name for another vendor), up to 10 `products` (product ID, localized price, ISO 8601 renewal period and free trial; 40 across all paywalls) and `presentable` (default `true`; `false` lists an offering without a paywall for your team: it is always reported, never checked with `paywallAvailability` and never opened by a card). Registration sends them so the dashboard shows where each paywall is built and what it sells. All are optional with defaults, so existing `ReceptionPaywall(id:title:)` code is unchanged; an invalid product detail or source is dropped, never the paywall.

## [1.3.0] — 2026-10-16

### Added

- Device registration and updates report the appearance your app sets in code (`Reception.shared.appearance`, as values that differ from the defaults, plus the asset-catalog accent color and `usesRemoteAppearance`). The dashboard's chat design editor starts from that design instead of the built-in defaults. Bundled images are reported only as present, never uploaded. Remote appearance precedence is unchanged.

## [1.2.0] — 2026-10-14

### Added

- Non-prompting APNs registration and notification-delegate helpers; existing push APIs are unchanged.
- Bundled resources load when the SDK is compiled through CocoaPods, as in the React Native package.

### Fixed

- The composer stays inside embedded chat bounds on iOS 26.

## [1.1.1] — 2026-10-09

### Fixed

- Team replies without a known author no longer show an empty avatar circle.

## [1.1.0] — 2026-10-06

### Added

- `welcomeIconCornerRadius` rounds local and uploaded welcome images, with an optional dashboard override. Symbols are unchanged.
- `welcomeIcon` with `Reception.WelcomeIcon` (`.symbol(_:)`, `.image(_:)`, `.hidden`), plus `welcomeIconColor`, `welcomeIconSize` and `welcomeIconOffset`, so the welcome icon can use an image bundled with your app.
- `hidesTitle`, `hidesWelcomeTitle` and `hidesWelcomeText`.
- `closeImage` for a close button image bundled with your app.
- `-ReceptionPreview welcome` and `-ReceptionPreview conversation` launch arguments open the chat with local example data in Debug simulator builds, so coding agents can screenshot it without tapping. They send and save nothing.

### Fixed

- Team names restore alongside cached photos before the first network response, including when only names are enabled. Refreshed names and removed members update the same session-scoped cache.
- Previously loaded team photos appear immediately after app restarts from a bounded, session-scoped disk cache. Photo removal, chat resets, logout and data deletion clear the relevant cached photos.
- Team photos stay in memory across chat openings, reuse unchanged photos when signed links refresh, and replace changed photos without flashing the placeholder. Removed photos are cleared when team details refresh.
- Replies reserve their avatar space while team details and photos load, preventing horizontal layout jumps when team photos are enabled.
- Automatic push environment detection now selects APNs sandbox on the simulator instead of ignoring its token. Physical-device detection is unchanged.
- A hidden chat title no longer reappears as plain navigation title text.
- Published visibility can show or hide elements independently of local appearance; unset visibility keeps the app's setting.
- A published close symbol overrides a local close image, and a published font design overrides a local custom font.

## [1.0.0] — 2026-10-01

First public release.

### Added

- `Reception.configure(appId:)` connects your app with its public App ID from the Reception dashboard.
- Native support chat with text and photos, opened with `Reception.shared.openChat()` or embedded as `ReceptionChatView`.
- Unread counts for your own entry point, with optional app icon badge.
- `identify(userId:name:email:)`, `setMetadata(_:)`, `logout()` and `deleteData()` for accounts, customer context, sign-out and account deletion.
- Identity verification with `identify(token:)` for tokens signed by your own server, and the `identityRejected` event.
- Push notifications for replies through `setPushToken(_:)` and `handlePushNotification(userInfo:openChat:)`, without a permission prompt.
- App Store review cards and paywall cards. Register `Reception.shared.paywalls`, present your own paywall from `onPaywall`, and limit offers with `paywallAvailability`.
- Local appearance options, plus remote appearance, texts, team photos and names published from the dashboard.
- Built-in text in 48 languages, following the app's language, with `languageOverride` for in-app language settings.
- Events through `onEvent` for your analytics.
- Automatic retries for interrupted sends and rate-limit waits that keep drafts and resume on their own.
- Setup check in Debug simulator builds that verifies message delivery.
- Device sessions with short-lived access, credentials in the Keychain, and a privacy manifest.
