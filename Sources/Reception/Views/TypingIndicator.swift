import SwiftUI

internal struct TypingIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startedAt = Date()
    @ScaledMetric(relativeTo: .body) private var diameter = Theme.typingDotDiameter
    @ScaledMetric(relativeTo: .body) private var spacing = Theme.typingDotSpacing

    var body: some View {
        TimelineView(.animation(minimumInterval: Theme.typingFrameInterval,
                                paused: reduceMotion || !Reception.shared.applicationActive)) { context in
            HStack(spacing: spacing) {
                ForEach(0..<Theme.connectionDotCount, id: \.self) { index in
                    let pulse = reduceMotion ? Theme.zero : Theme.typingPulse(
                        elapsed: context.date.timeIntervalSince(startedAt), index: index)
                    Circle().fill(Theme.muted)
                        .frame(width: diameter, height: diameter)
                        .opacity(Theme.typingRestingOpacity + pulse * Theme.typingOpacityRange)
                        .scaleEffect(Theme.typingRestingScale + pulse * Theme.typingScaleRange)
                        .offset(y: -pulse * Theme.typingDotLift)
                }
            }
        }
        .frame(minHeight: Theme.composerLineHeight)
        .padding(.horizontal, Theme.bubbleHorizontal)
        .padding(.vertical, Theme.bubbleVertical)
        .background(Theme.secondary, in: BubbleShape())
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Theme.string("Support is typing"))
    }
}
