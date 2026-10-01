import Reception
import SwiftUI

@MainActor
struct RootView: View {
    var authStore: AuthStore

    var body: some View {
        Group {
            if authStore.userId != nil {
                SignedInTabs(authStore: authStore)
            } else {
                SignInView(authStore: authStore)
            }
        }
    }
}
