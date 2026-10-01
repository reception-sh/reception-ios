# UIKit example

A single-scene UIKit navigation app using SDK-owned chat presentation.
See the [UIKit guide](https://reception.sh/docs/uikit) in the website docs.

Generate the project with `xcodegen generate --spec Examples/UIKit/project.yml` from
the SDK root, or open the checked-in project. Build its `UIKitExample`
scheme for an available iOS simulator using Xcode 26.

Replace `app_YOUR_APP_ID` in `AppDelegate.swift` with the App ID from your Reception
dashboard. The local package reference uses this repository.

The app has a Support button and a Details navigation item. Details opens another
UIKit controller with a Support bar button. Verify send/receive, close, unread,
background/foreground, and return navigation. The SDK observes app lifecycle itself.

This example has no accounts or push permission flow. It does not verify logout,
account deletion or APNs; the Accounts example covers those.
