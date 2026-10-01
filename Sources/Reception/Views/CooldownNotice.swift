import SwiftUI

internal struct CooldownNotice: View {
    let cooldown: ServerCooldowns.Cooldown
    @ScaledMetric(relativeTo: .footnote) private var textSize = Theme.connectionSize

    var body: some View {
        TimelineView(Theme.countdownTicks) { context in
            HStack(alignment: .firstTextBaseline, spacing: Theme.small) {
                Image(systemName: "clock").accessibilityHidden(true)
                Text(CooldownText.notice(cooldown, now: context.date))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(Theme.textFont(size: Theme.connectionSize, scaledSize: textSize, relativeTo: .footnote))
        .foregroundStyle(Theme.muted)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}
