import SwiftUI

internal struct ActionCard: View {
    let text: String
    let label: String
    let symbol: String
    let accessory: String
    var style = Reception.Appearance.CardStyle()
    var isAvailable = true
    let action: () -> Void
    @ScaledMetric(relativeTo: .caption) private var iconSize = Theme.cardIconSize

    var body: some View {
        Group {
            // Without text, the button stands alone instead of sitting in an empty card.
            if text.isEmpty {
                content
            } else {
                content
                    .padding(.horizontal, Theme.bubbleHorizontal)
                    .padding(.vertical, Theme.bubbleVertical)
                    .background(Theme.secondary, in: BubbleShape())
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Theme.small) {
            if !text.isEmpty {
                Text(text).font(Theme.bodyFont).foregroundStyle(Theme.incomingForeground)
            }
            Button { action() } label: {
                HStack(spacing: Theme.small) {
                    AppearanceIconView(icon: style.icon ?? .symbol(symbol), size: scaledIconSize).accessibilityHidden(true)
                    Text(label)
                        .multilineTextAlignment(.center)
                    AppearanceIconView(icon: style.accessory ?? .symbol(accessory), size: scaledIconSize, weight: .bold)
                        .accessibilityHidden(true)
                }
                .font(Theme.bodyFont.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: Theme.control)
                .padding(.horizontal, Theme.bubbleHorizontal)
                .foregroundStyle(style.buttonText ?? Theme.outgoingForeground)
                .background(isAvailable ? style.button ?? Reception.resolvedAppearance.accentColor : Theme.muted, in: BubbleShape())
            }
            .buttonStyle(.plain)
            .disabled(!isAvailable)
            .accessibilityLabel(label)
            if !isAvailable {
                Text(Theme.string("No longer available"))
                    .font(Theme.captionFont).foregroundStyle(Theme.muted)
            }
        }
    }

    /// iconSize carries the Dynamic Type factor for the built-in size.
    private var scaledIconSize: CGFloat { iconSize * (style.iconSize ?? Theme.cardIconSize) / Theme.cardIconSize }
}
