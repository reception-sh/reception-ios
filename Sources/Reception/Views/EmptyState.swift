import SwiftUI

internal struct EmptyState: View {
    @ScaledMetric(relativeTo: .title) private var iconSize = Theme.emptyIconSize
    @ScaledMetric(relativeTo: .title2) private var titleSize = Theme.emptyTitleSize
    @ScaledMetric(relativeTo: .subheadline) private var subtitleSize = Theme.emptySubtitleSize

    var body: some View {
        VStack(spacing: Theme.small) {
            let appearance = Reception.resolvedAppearance
            let icon = appearance.welcomeIcon?.icon ?? .symbol("bubble.left.and.bubble.right")
            let scale = iconSize / Theme.emptyIconSize
            let radius = appearance.welcomeIconCornerRadius
            if !icon.isHidden {
                // iconSize carries the Dynamic Type factor for the built-in size.
                AppearanceIconView(icon: icon, size: (appearance.welcomeIconSize ?? Theme.emptyIconSize) * scale,
                    imageCornerRadius: (radius.isFinite ? min(max(radius, 0), 80) : 0) * scale)
                    .foregroundStyle(appearance.welcomeIconColor ?? Theme.tertiary)
                    .offset(appearance.welcomeIconOffset)
                    .padding(.bottom, Theme.small)
                    .accessibilityHidden(true)
            }
            if !appearance.hidesWelcomeTitle {
                Text(appearance.welcomeTitle).font(Theme.textFont(size: Theme.emptyTitleSize, scaledSize: titleSize, relativeTo: .title2, weight: .semibold))
            }
            if !appearance.hidesWelcomeText {
                Text(appearance.welcomeText)
                    .font(Theme.textFont(size: Theme.emptySubtitleSize, scaledSize: subtitleSize, relativeTo: .subheadline)).foregroundStyle(Theme.muted)
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, Theme.spacing)
        .padding(.bottom, Theme.emptyBottomInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
