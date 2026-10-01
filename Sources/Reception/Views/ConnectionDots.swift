import SwiftUI

internal struct ConnectionDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var raised = false

    var body: some View {
        HStack(spacing: Theme.connectionDotSpacing) {
            ForEach(0..<Theme.connectionDotCount, id: \.self) { index in
                Circle().fill(Theme.muted)
                    .frame(width: Theme.connectionDotDiameter, height: Theme.connectionDotDiameter)
                    .offset(y: raised ? -Theme.connectionDotLift : Theme.zero)
                    .animation(reduceMotion ? nil : Theme.connectionDotAnimation(index: index), value: raised)
            }
        }
        .onChange(of: reduceMotion, initial: true) { raised = !reduceMotion }
    }
}
