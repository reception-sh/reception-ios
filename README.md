# Reception iOS SDK

The Reception SDK adds native in-app support chat to iOS apps, with replies managed in the hosted Reception dashboard.

**Reception** is a hosted support chat for mobile apps. Your customers write to you in a native chat inside your app on iOS and Android, and your team replies from the Reception dashboard, Slack or Telegram. This repository is the native iOS SDK for SwiftUI and UIKit apps, installed with Swift Package Manager.

- **Docs:** [Native iOS guide](https://reception.sh/docs/native-ios) · [All guides](https://reception.sh/docs)
- **Price:** $30 per month or $250 per year per organization, plus sales tax or VAT where it applies. One subscription covers every app and every team member.
- **Free trial:** [Create an account](https://reception.sh/login) and set up your app. Your first subscription starts with a 7-day free trial: you add a card in Stripe Checkout, and nothing is charged if you cancel within the 7 days. Before you subscribe, you can reply to your own test device.
- **Other platforms:** [iOS](https://github.com/reception-sh/reception-ios) · [Android](https://github.com/reception-sh/reception-android) · [React Native](https://github.com/reception-sh/reception-react-native) · [Flutter](https://github.com/reception-sh/reception-flutter)

Requires iOS 17+, Xcode 26, and Swift Package Manager.

## Setup

The easiest setup is to choose **Copy setup prompt** in your Reception dashboard and paste it into a coding agent with your iOS project open.

In Xcode, choose **File → Add Package Dependencies**, enter `https://github.com/reception-sh/reception-ios.git`, keep **Up to Next Major Version**, and add the **Reception** library to your app target.

Import `Reception` and configure once at launch on the main actor, using the App ID from your dashboard:

```swift
Reception.configure(appId: "app_…")
```

Open chat from your own button or settings row on the main actor:

```swift
Reception.shared.openChat()
```

## Documentation

- [Setup](https://reception.sh/docs/get-started)
- [Native iOS guide](https://reception.sh/docs/native-ios)
- [All guides](https://reception.sh/docs) · [Index for AI agents](https://reception.sh/llms.txt)

[Examples](Examples/README.md) · [Contributing](CONTRIBUTING.md) · [MIT license](LICENSE)
