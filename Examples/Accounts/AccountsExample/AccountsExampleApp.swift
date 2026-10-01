import Reception
import SwiftUI

@main
struct AccountsExampleApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var authStore = AuthStore()

    init() {
        // Replace with the App ID from your Reception dashboard.
        Reception.configure(appId: "app_YOUR_APP_ID")
        let store = authStore
        Reception.shared.onEvent = { event in
            if case .identityRejected(let error) = event { store.supportIdentityRejected(error) }
        }
        // identify() after configure(), so a restored session is attached to the right device.
        authStore.restoreSession()
    }

    var body: some Scene {
        WindowGroup {
            RootView(authStore: authStore)
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                Task { await registerIfAuthorized() }
            }
        }
    }
}

/// Maintainer settings from the scheme environment or from launch arguments such as `-ReceptionTokenURL http://127.0.0.1:3900/reception-token`.
enum MaintainerSettings {
    static func value(_ environment: String, argument: String) -> String? {
        if let value = ProcessInfo.processInfo.environment[environment], !value.isEmpty { return value }
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: argument), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}
