import SwiftUI

internal struct SendingStatus: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startedAt = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: Theme.typingFrameInterval,
                                paused: reduceMotion || !Reception.shared.applicationActive)) { context in
            HStack(alignment: .firstTextBaseline, spacing: Theme.zero) {
                Text(Theme.string("Sending"))
                ForEach(0..<Theme.connectionDotCount, id: \.self) { index in
                    Text(".")
                        .opacity(reduceMotion ? Theme.fullOpacity : Theme.sendingDotRestingOpacity +
                                 Theme.sendingDotOpacityRange * Theme.typingPulse(
                                    elapsed: context.date.timeIntervalSince(startedAt), index: index))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Theme.string("Sending…"))
    }
}
