# AGENTS.md — Rules for everyone who writes code here

These rules are for anyone changing this SDK, including coding agents. Customers who add the SDK
to their app start at [README.md](README.md) and the [setup guide](https://reception.sh/docs/get-started).

`Reception` is the iOS SDK for an in-app support chat. It talks to the hosted Reception service
through its `/v1` API. Maintainers with access to the private Reception backend repository read
its SDK specification (`docs/SDK_SPEC.md`) before changing behavior that touches the API: paths,
headers and field names there are binding. Without that access, treat the existing client code
in `Sources/Reception/Client/` as the contract and don't change request or response shapes.

## Stack (fixed)

Swift Package, swift-tools-version 6.0, Language Mode 5 with `-strict-concurrency=complete`,
Platform iOS 17+, SwiftUI, `@Observable`, URLSession + Codable, Keychain, String Catalog
(48 supported languages). **No dependencies.** Must build in Xcode 26 without warnings.

## The style we aim for

**Extremely clean, simple, safe at the boundaries.** The SDK runs in other apps: it must
never crash, never block startup, never require anything from the host.

- One file, one responsibility. Nothing over ~200 lines.
- Keep the public API small. Everything else `internal`. No `public` "just in case".
- Errors at the boundaries: every network call returns `Result`/throws typed errors; the
  ViewModel translates them into UI state. No `try!`, no `!` on optionals, no
  `fatalError` except for actual programming errors (and there are none here).
- Keychain and UserDefaults access each have their own file and catch all errors themselves.
- `@MainActor` on ViewModels and anything that touches UI. Networking in `async` functions,
  no callbacks, no Combine.
- Views contain only layout. No networking, no logic in Views. Colors, spacing, radii
  exclusively from `Theme`/`Appearance`, nothing hardcoded.
- No dead code, no commented-out blocks. Comments only for the *why*.
- Names: clear, no abbreviations. Files are named after their main type.
- Use `Log.error`, `Log.info`, or `Log.debug`; never `print`/`NSLog`, and never log access
  tokens, session secrets, identity tokens or their claims, identity secrets, push token values,
  user IDs, names, email addresses, metadata values, message text, image URLs, conversation
  content, or service credentials.
- **Focused unit tests only**, for security-relevant parsing and concurrency that is easy to get
  subtly wrong (identity token decoding, single-flight token refresh, authenticated action delivery),
  and focused paywall API contract checks. Tests never touch the
  Keychain (the simulator test host has no Keychain entitlement) and stub HTTP with
  `URLProtocol`. Everything else is verified with `xcodebuild build` for the simulator (without
  warnings), the examples, and a manual run against the hosted service. See
  [CONTRIBUTING.md](CONTRIBUTING.md). Report actual output.

## Structure

```
Sources/Reception/
  Reception.swift            Facade: configuration, presentation, push, logout, deleteData
  ReceptionIdentity.swift    identify, identity tokens, metadata
  Appearance.swift           appearance options and ReceptionEvent
  ReceptionError.swift, ReceptionPaywall.swift, CloseIcon.swift   other public types
  Localization.swift, Log.swift, Version.swift                    built-in texts, logging, SDK version
  Theme.swift                internal tokens (colors, spacing, radius), Liquid Glass on iOS 26 and later
  Client/                    ReceptionAPI, device session and refresh, DeviceStore, Keychain, uploads, setup check
  Configuration/             remote appearance and its cache
  Models/                    Message, Conversation, Attachment, MessageStatus
  ViewModel/                 ChatModel and its delivery, recovery and connection parts
  Views/                     ReceptionChatView, bubbles, composer, cards, presenter, banners
  Resources/                 Localizable.xcstrings, PrivacyInfo.xcprivacy
Examples/                    Basic, Accounts and UIKit example apps
Tests/ReceptionTests/        focused unit tests
```

## UI

Native, like an iOS sheet: system font, Dynamic Type, Dark Mode, keyboard avoidance without
jumps, auto-scroll on new messages. Liquid Glass (iOS 26) for the composer, chat title and
the sheet's optional close button, cleanly separated with `if #available`; Materials below iOS 26.
The host app owns entry buttons, settings rows, positioning and unread badges.
`Reception.shared.openChat()` presents the standard chat sheet over the active app window;
`ReceptionChatView()` remains available for host-owned presentation.
The host registers `Reception.shared.paywalls` and presents its own paywall from
`onPaywall`; the SDK keeps chat open and emits `.paywallOpened`. An optional
`paywallAvailability` check filters them into `availablePaywalls`, which drives cards and
the device sync; the host calls `refreshPaywalls(invalidate: true)` after subscription changes. Action receipts use
`conversation/action-click` and record an open, never a purchase.

**Distinct identity:** The chat follows Apple's patterns for grouping,
status rows and glass composers, but remains a distinct support chat rather than a
1:1 copy of the Messages app. The host app sets `appearance.accentColor`; the
default is `Color.accentColor`, no fixed Messages blue. A photo icon, send arrow,
speech-bubble empty state, its own status/connection text and timestamp formats define
the interface. Bubbles have Continuous Corners with radius 16, padding 10/14 and
no tail. Measurements from Messages serve as a guide; integration into the host
and consistency on iOS 17/18/26 take priority over an exact reproduction of those dimensions.

## Git and releases

Small, focused commits. Customers install tagged versions, never `main`. A release is a
[CHANGELOG.md](CHANGELOG.md) entry plus a semantic version tag (`1.0.1` fix, `1.1.0` feature,
`2.0.0` breaking change); see [CONTRIBUTING.md](CONTRIBUTING.md#releases).
