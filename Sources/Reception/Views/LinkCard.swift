import SwiftUI

internal struct LinkCard: View {
    let text: String
    let label: String?
    let url: URL
    let isInApp: Bool
    let openLink: (URL) -> Void

    var body: some View {
        ActionCard(text: text, label: label ?? Theme.string("Open link"), symbol: "link",
                   accessory: isInApp ? "chevron.right" : "arrow.up.right",
                   style: Reception.resolvedAppearance.linkCard) {
            openLink(url)
        }
    }
}
