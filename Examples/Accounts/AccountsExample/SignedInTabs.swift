import SwiftUI

@MainActor
struct SignedInTabs: View {
    var authStore: AuthStore

    var body: some View {
        TabView {
            NavigationStack {
                HomeView(authStore: authStore)
            }
            .tabItem { Label("Home", systemImage: "house") }

            NavigationStack {
                AccountView(authStore: authStore)
            }
            .tabItem { Label("Account", systemImage: "person.crop.circle") }
        }
    }
}
