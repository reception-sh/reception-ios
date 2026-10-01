import SwiftUI

internal struct SendingDisabledNotice: View {
    let text: String
    let height: CGFloat
    @ScaledMetric(relativeTo: .footnote) private var textSize = Theme.sendingDisabledSize

    var body: some View {
        Text(text)
            .font(Theme.textFont(size: Theme.sendingDisabledSize, scaledSize: textSize, relativeTo: .footnote)).lineLimit(Theme.sendingDisabledLineLimit)
            .multilineTextAlignment(.center)
            .minimumScaleFactor(Theme.sendingDisabledMinimumScale)
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, Theme.spacing)
            .frame(maxWidth: .infinity)
            .frame(height: height)
    }
}
