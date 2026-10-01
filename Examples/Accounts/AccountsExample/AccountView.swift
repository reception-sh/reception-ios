import Reception
import SwiftUI
import UIKit
import UserNotifications

@MainActor
struct AccountView: View {
    var authStore: AuthStore
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var showsDeleteConfirmation = false

    var body: some View {
        List {
            Section("Profile") {
                LabeledContent("Name", value: authStore.name ?? "")
                LabeledContent("Email", value: authStore.email ?? "")
            }

            Section("Notifications") {
                LabeledContent("Status", value: notificationStatus.displayText)
                if notificationStatus != .authorized {
                    Button("Enable notifications") {
                        Task { await requestNotificationPermission() }
                    }
                }
            }

            Section("Support") {
                Button {
                    Reception.shared.openChat()
                } label: {
                    HStack {
                        Text("Support")
                        Spacer()
                        if Reception.shared.unreadCount > 0 {
                            Text(Reception.shared.unreadCount, format: .number)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Account") {
                Button("Sign out") {
                    authStore.signOut()
                }
                Button("Delete account", role: .destructive) {
                    showsDeleteConfirmation = true
                }
                .disabled(authStore.isDeleting)
                if authStore.isDeleting {
                    ProgressView("Deleting account…")
                }
                if let deletionError = authStore.deletionError {
                    Text(deletionError).foregroundStyle(.red)
                    Button("Retry deletion") {
                        Task { await authStore.deleteAccount() }
                    }
                    .disabled(authStore.isDeleting)
                }
            }
        }
        .navigationTitle("Account")
        .task { await refreshNotificationStatus() }
        .confirmationDialog("Delete your account?", isPresented: $showsDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete account", role: .destructive) {
                Task { await authStore.deleteAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your support conversations. This cannot be undone.")
        }
    }

    private func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationStatus = settings.authorizationStatus
    }

    private func requestNotificationPermission() async {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        if granted {
            UIApplication.shared.registerForRemoteNotifications()
        }
        await refreshNotificationStatus()
    }
}

private extension UNAuthorizationStatus {
    var displayText: String {
        switch self {
        case .authorized: "Authorized"
        case .denied: "Denied"
        case .notDetermined: "Not determined"
        case .provisional: "Provisional"
        case .ephemeral: "Ephemeral"
        @unknown default: "Unknown"
        }
    }
}
