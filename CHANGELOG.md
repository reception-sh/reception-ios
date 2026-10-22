# Changelog

All notable changes to the Reception iOS SDK are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project follows [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- `Reception.shared.track(_:opensChat:)` reports app events, such as a closed paywall, for automations set up in the dashboard. An automation's message arrives in the chat once; with `opensChat: true` the chat opens every time.
- While an automation listens for them, the SDK reports `trial_cancelled`, `subscription_cancelled`, `billing_issue` and `subscription_expired` from the App Store when the app becomes active.
- Device registration and updates report whether the person has paid access in the App Store.
- The team's typing indicator shows briefly before an automation's message appears in a chat it opened.

### Fixed

- The chat no longer opens on a screen that is being dismissed, where it would close with that screen.

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
