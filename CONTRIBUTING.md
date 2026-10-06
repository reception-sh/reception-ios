# Contributing to the Reception SDK

This guide is for anyone changing the Reception SDK. Customers embed the SDK in their iOS app and use the hosted Reception service and dashboard; their setup starts at [README.md](README.md) and the [setup guide](https://reception.sh/docs/get-started).

Read [AGENTS.md](AGENTS.md) before working on the SDK. Maintainers with access to the private Reception backend repository also read its SDK specification (`docs/SDK_SPEC.md`); the backend and service operations live there.

## Local SDK and example apps

Use Xcode 26 with an installed iOS simulator. Open the package directory for SDK work; use Xcode’s **Add Local…** when a host app needs to exercise your local SDK changes. The apps in `Examples/` reference the package locally through their `project.yml`.

Device registration and updates include `bundleId` from `Bundle.main.bundleIdentifier`, omitting it when nil.

The examples connect to the hosted Reception service. Replace `app_YOUR_APP_ID` in each example with the App ID of your test app, and do not commit it.

To test against a local backend, call `Reception.configure(appId:serviceURL:)` from `@_spi(ReceptionTesting) import Reception` in a Debug build instead of `configure(appId:)`, and allow local networking in the test app's App Transport Security settings. Release builds don't contain this call.

The setup check runs in Debug simulator builds: launch the app with `-ReceptionSetupCheck <App ID>` and read the `com.reception.sdk` / `SetupCheck` log lines. It sends one real message.
Launch with `-ReceptionPreview welcome` or `-ReceptionPreview conversation` to open the chat with local example data for screenshots; it sends and saves nothing.

Build all three examples for an available simulator and verify that each Support entry presents the SDK-owned sheet. Manually verify message delivery against the hosted service when required by AGENTS.md. Report actual build results and observed behavior, or the precise reason a check was not run.

## Simulator push notifications

`setPushToken(_:)` uses APNs sandbox automatically on the simulator. The host still needs
push capability, notification permission through its existing flow, and a real APNs token.
Use an APNs-capable simulator on supported Mac hardware and configure matching sandbox
credentials in the dashboard.

Verify actual receipt after an APNs request; a successful chat setup check or `simctl push`
only verifies its own path. Before shipping, also test push on a physical iPhone. Do not log tokens.

## Unit tests

`Tests/ReceptionTests` holds focused tests for identity token decoding, the single-flight token refresh, server cooldowns (retry scope parsing, the network-boundary gate, persistence and send intent), and localization. Run them on an installed simulator:

```sh
xcodebuild test -scheme Reception -destination 'platform=iOS Simulator,name=iPhone 17'
```

The package's test host has no Keychain entitlement, so every Keychain call fails with `errSecMissingEntitlement` (-34018). Tests therefore set session credentials in memory and never touch the Keychain. HTTP is stubbed with a `URLProtocol` subclass registered for `URLSession.shared`.

Submitted messages with a temporary network/server failure persist their retry intent. On a cold restart and visible chat opening, history reconciliation precedes recovery when available; temporary loading failures do not strand the queue. The existing serial driver retains client IDs, photos, backoff and the eight-attempt budget. Reopening does not replenish an existing budget. Interrupted pending sends share this path. Cancel, permanent failures and unsent drafts stay manual; older failed caches without retry intent are not guessed. Verify both a failed first registration and a server-committed message whose response was lost against the hosted service. These real app checks use the host's Keychain entitlement.

## Rate-limit cooldowns

The service's `429` responses, and its two scoped capacity `503`s, carry `Retry-After` and an optional `error.retryScope`. The SDK behavior is specified under "Server cooldowns" in the private backend repository's `docs/SDK_SPEC.md`. To inspect every visual state without pushing a real backend to its limits, the Basic example has deterministic fixtures. They compile only in Debug simulator builds:

Opening the chat or foregrounding a visible chat can attach `limits=1` to its existing conversation GET when a message/photo cooldown has more than 60 seconds left. A persisted timestamp bounds these attempts to one per minute, including failed attempts. There is no polling timer or extra status request. A current response can release only the scopes checked; unknown or malformed values retain the wait. After merging confirmed messages and permissions, eligible limit-held messages resume through the normal serial retry driver. Already-expired holds resume on opening too, without a status query. Explicit Cancel, ordinary failed messages and unsent drafts do not resume this way. The batch stops on a new failure or when the chat leaves the screen.

```sh
-ReceptionCooldownFixture message-short   # also: message-long, message-expired, photo, requests, session, stream, blocked, verification
```

A `URLProtocol` answers every Reception API request with scripted replies; the chat, its state and its storage are the production code. Each launch starts a fresh chat; add `-ReceptionCooldownFixtureRelaunch` to keep the previous one and check that stored waits survive a relaunch. Requests are appended to `Library/Caches/reception-fixture-requests.log` in the app container, so you can confirm that nothing is sent during a wait. Fixture screenshots show SDK states only. They do not prove that the service enforces a limit: verify that separately against the hosted service.

## Identity verification

Enable identity verification for your test app in the dashboard and copy its identity secret. Start the demo token server from the SDK root; it signs any user, listens on `127.0.0.1` only, and refuses to start without `RECEPTION_DEMO=1` or with `NODE_ENV=production`:

```sh
RECEPTION_DEMO=1 RECEPTION_IDENTITY_SECRET=<test app secret> node Examples/Accounts/token-server.mjs
```

Set `RECEPTION_TOKEN_URL` in the Accounts scheme to the printed address, sign in, and send a message. The dashboard should show the customer as **Verified**. Never copy the demo server into a real deployment and never put the identity secret into an app target or a shared scheme.

## Photo uploads

Photos are reserved with a request ID and a SHA-256 checksum, then uploaded with exactly the headers the reservation returns, including `If-Match`. A `412` from a repeated upload means an earlier upload probably succeeded before its response was lost; the SDK continues with the message, and the server verifies the stored bytes before **Sent**. A `409 upload_incomplete` clears the draft's upload mapping, so the next attempt uploads again. A `400 invalid_attachment` means the image was rejected. Verify a lost upload response, a `412` without a stored object, and deletion during an upload as separate cases.

## Paywall cards

The Basic example registers `support_chat` and opens a placeholder sheet above chat.
Send a paywall card from the dashboard to inspect the available and unavailable card states.
In live chat, send a PAYWALL message from the dashboard and verify that the callback leaves
chat open. Device POST/PATCH payloads always include the current `availablePaywalls` array, including
an empty array. Without `paywallAvailability` it equals `paywalls`. REVIEW and PAYWALL receipts share `POST /v1/conversation/action-click`
with `{ "messageId": "…" }`; message responses expose nullable `actionClickedAt`.
Clicks are persisted and retried independently of host paywall presentation, not purchase receipts.

## Releases

Customers install tagged versions with the rule **Up to Next Major Version**; commits on `main` reach nobody until a tag exists.

1. Choose the version: patch (`1.0.1`) for fixes, minor (`1.1.0`) for new features, major (`2.0.0`) only when customers must change their code.
2. Set `SDKVersion.current` in `Sources/Reception/Version.swift` to that version.
3. Move the `Unreleased` entries in [CHANGELOG.md](CHANGELOG.md) under the new version and date.
4. Run the unit tests and build all three examples.
5. Commit, tag the commit with the bare version (`git tag 1.0.1`, no `v` prefix), push `main` and the tag, and publish a GitHub release with the CHANGELOG text.

Never move or delete a published tag; release a new version instead.
