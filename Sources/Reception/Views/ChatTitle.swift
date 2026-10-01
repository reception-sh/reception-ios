import SwiftUI

internal struct ChatTitle: View {
    var body: some View {
        if Reception.resolvedAppearance.hidesTitle {
            EmptyView()
        } else if #available(iOS 26, *) {
            title.glassEffect(.regular, in: Capsule())
        } else {
            title.background(.regularMaterial, in: Capsule())
        }
    }

    private var title: some View {
        Text(Reception.resolvedAppearance.title)
            .font(Theme.titleFont)
            .foregroundStyle(Theme.foreground)
            .padding(.horizontal, Theme.titleChipHorizontal)
            .padding(.vertical, Theme.titleChipVertical)
            .accessibilityAddTraits(.isHeader)
    }
}
