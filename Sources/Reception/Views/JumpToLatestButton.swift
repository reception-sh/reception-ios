import SwiftUI

/// Floats above the composer when replies arrived below a reader who is further up: "⌄ 3 new messages".
internal struct JumpToLatestButton: View {
    let unseenCount: Int
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var scale = Theme.unit

    private var height: CGFloat { Theme.jumpToLatestHeight * min(scale, Theme.jumpToLatestMaximumScale) }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.jumpToLatestLabelSpacing) {
                Image(systemName: "chevron.down")
                    .font(.system(size: Theme.jumpToLatestIcon * min(scale, Theme.jumpToLatestMaximumScale), weight: .semibold))
                    .foregroundStyle(Reception.resolvedAppearance.accentColor)
                Text(Self.unreadText(for: unseenCount) ?? "")
                    .font(Theme.subheadlineFont.weight(.medium).monospacedDigit())
                    .foregroundStyle(Theme.foreground)
                    .lineLimit(1)
                    .fixedSize()
                    .contentTransition(.numericText(value: Double(unseenCount)))
            }
            .padding(.horizontal, Theme.jumpToLatestHorizontal)
            .frame(minHeight: height)
            .modifier(JumpToLatestSurface())
            .frame(minWidth: Theme.jumpToLatestTarget, minHeight: Theme.jumpToLatestTarget)
            .contentShape(Rectangle())
            .animation(reduceMotion ? nil : Theme.messageAnimation, value: unseenCount)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Theme.string("Jump to latest message"))
        .accessibilityValue(Self.localizedCount(unseenCount))
    }

    static func unreadText(for count: Int) -> String? {
        ChatScrollState.unreadText(for: count, locale: ReceptionLocalization.locale, format: localizedCount)
    }

    private static func localizedCount(_ count: Int) -> String {
        String(localized: "\(count) new messages", bundle: ReceptionLocalization.bundle, locale: ReceptionLocalization.locale)
    }
}

/// Liquid Glass like the composer on iOS 26. Below that a denser material than the composer's, with a hairline and a
/// barely visible shadow, because the small control floats over colored bubbles that would tint a thin material.
private struct JumpToLatestSurface: ViewModifier {
    @Environment(\.displayScale) private var displayScale

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(.regular.interactive(), in: .capsule)
        } else {
            content.background(.thickMaterial, in: Capsule())
                .overlay { Capsule().strokeBorder(Theme.separator, lineWidth: 1 / displayScale) }
                .shadow(color: Theme.jumpToLatestShadow, radius: Theme.jumpToLatestShadowRadius, y: Theme.jumpToLatestShadowY)
        }
    }
}
