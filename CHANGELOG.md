# Changelog

All notable changes to the Reception iOS SDK are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project follows [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- `welcomeIconCornerRadius` rounds local and uploaded welcome images, with an optional dashboard override. Symbols are unchanged.

- `welcomeIcon` with `Reception.WelcomeIcon` (`.symbol(_:)`, `.image(_:)`, `.hidden`), plus `welcomeIconColor`, `welcomeIconSize` and `welcomeIconOffset`, so the welcome icon can use an image bundled with your app.
- `hidesTitle`, `hidesWelcomeTitle` and `hidesWelcomeText`.
- `closeImage` for a close button image bundled with your app.

### Fixed

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
