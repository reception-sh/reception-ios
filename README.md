# Reception iOS SDK

The Reception SDK adds native in-app support chat to iOS apps, with replies managed in the hosted Reception dashboard.

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
- [All guides](https://reception.sh/docs) · [Index for AI agents](https://reception.sh/llms.txt)

[Examples](Examples/README.md) · [Contributing](CONTRIBUTING.md) · [MIT license](LICENSE)
