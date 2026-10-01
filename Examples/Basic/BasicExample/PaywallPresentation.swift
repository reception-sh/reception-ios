import SwiftUI
import Reception

@MainActor
enum PaywallPresentation {
    static func configure() {
        Reception.shared.paywalls = [ReceptionPaywall(id: "support_chat", title: "Support offer")]
        Reception.shared.onPaywall = { id in
            guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
                  var presenter = scene.windows.first(where: \.isKeyWindow)?.rootViewController else { return }
            while let presented = presenter.presentedViewController { presenter = presented }
            presenter.present(UIHostingController(rootView: PlaceholderPaywall(id: id)), animated: true)
        }
    }
}

private struct PlaceholderPaywall: View {
    @Environment(\.dismiss) private var dismiss
    let id: String

    var body: some View {
        NavigationStack {
            ContentUnavailableView("Your paywall", systemImage: "gift",
                                   description: Text("Replace this placeholder with your in-app purchase view for \(id)."))
                .toolbar { Button("Done") { dismiss() } }
        }
    }
}
