import SwiftUI

internal struct ConnectionBanner: View {
    let state: ConnectionState
    @ScaledMetric(relativeTo: .footnote) private var textSize = Theme.connectionSize

    var body: some View {
        HStack(spacing: Theme.small) {
            Image(systemName: icon)
                .imageScale(.medium)
                .accessibilityHidden(true)
            HStack(alignment: .center, spacing: Theme.zero) {
                Text(title).contentTransition(.opacity)
                if state == .connecting {
                    ConnectionDots().padding(.leading, Theme.connectionDotTextSpacing)
                        .accessibilityHidden(true)
                }
            }
        }
        .font(Theme.textFont(size: Theme.connectionSize, scaledSize: textSize, relativeTo: .footnote, weight: .medium))
        .foregroundStyle(state == .connecting || state == .paused ? Theme.muted : (state == .connected ? Theme.success : Theme.error))
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state == .connecting ? Theme.string("Connecting…") : title)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var title: String {
        switch state {
        case .hidden, .offline: Theme.string("No connection")
        case .connecting: Theme.string("Connecting")
        case .connected: Theme.string("Connected")
        case .paused: Theme.string("Live updates paused")
        }
    }

    private var icon: String {
        switch state {
        case .offline: "wifi.slash"
        case .paused: "pause.circle"
        default: "wifi"
        }
    }
}
