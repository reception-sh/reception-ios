import SwiftUI

internal struct ReviewCard: View {
    @Environment(\.openURL) private var openURL
    let text: String
    let label: String?
    let url: URL
    let openReview: (URL, OpenURLAction) -> Void

    var body: some View {
        ActionCard(text: text, label: label ?? Theme.string("Rate on the App Store"), symbol: "star.fill", accessory: "arrow.up.right",
                   style: Reception.resolvedAppearance.reviewCard) {
            openReview(url, openURL)
        }
    }
}
