# Examples

Example apps for trying the SDK and verifying changes to it. Customer setup lives in the website docs at [Setup](https://reception.sh/docs/get-started).

[Basic](Basic/) is a SwiftUI app with a Home tab, a settings support entry point, and a language picker. It demonstrates SDK-owned chat presentation without accounts or push integration.

[UIKit](UIKit/) keeps its UIKit navigation hierarchy as the window root. It demonstrates SDK-owned chat presentation and unread observation with `withObservationTracking`.

[Accounts](Accounts/) is a SwiftUI app with local sign-in, session restoration, sign-out, and account deletion with retry. It also demonstrates a Support row with an unread badge and host-owned notification permission, APNs registration, and notification routing.

Accounts also shows identity verification. After sign-in and on every launch, `fetchReceptionToken()` requests a token from the URL in `RECEPTION_TOKEN_URL` and passes it to `Reception.shared.identify(token:)`. Without that variable, the chat stays unverified. The app contains neither the identity secret nor any signing code.

To try it locally, enable identity verification for your test app in the dashboard and run the demo token server on your Mac:

```sh
RECEPTION_DEMO=1 RECEPTION_IDENTITY_SECRET=<your test app's identity secret> node Examples/Accounts/token-server.mjs
```

Then set `RECEPTION_TOKEN_URL` in the Accounts scheme to the address the server prints. The demo server signs any user, so it is only for trying the example and must never be deployed. It listens on `127.0.0.1` only and refuses to start without `RECEPTION_DEMO=1` or with `NODE_ENV=production`. The example sends its local session value in `Authorization`, and the demo server uses that value as the user ID; a real server takes the user from its own authenticated session instead.
