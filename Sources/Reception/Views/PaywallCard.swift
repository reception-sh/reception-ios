import SwiftUI

internal struct PaywallCard: View {
    let text: String
    let label: String?
    let isAvailable: Bool
    let openPaywall: () -> Void

    var body: some View {
        ActionCard(text: text, label: label ?? Theme.string("View offer"), symbol: "gift.fill", accessory: "chevron.right",
                   style: Reception.resolvedAppearance.offerCard, isAvailable: isAvailable, action: openPaywall)
    }
}
