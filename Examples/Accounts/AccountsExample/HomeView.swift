import Reception
import SwiftUI

@MainActor
struct HomeView: View {
    var authStore: AuthStore

    var body: some View {
        VStack(spacing: 16) {
            Text("Welcome, \(authStore.name ?? "")")
                .font(.title2.weight(.semibold))
            Text("Glad to have you back.")
                .foregroundStyle(.secondary)
            Button("Contact support") {
                Reception.shared.openChat()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .navigationTitle("Home")
    }
}
