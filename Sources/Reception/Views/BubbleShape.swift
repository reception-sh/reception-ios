import SwiftUI

internal struct BubbleShape: Shape {
    func path(in rect: CGRect) -> Path {
        RoundedRectangle(cornerRadius: min(Theme.bubbleRadius, rect.height / 2), style: .continuous).path(in: rect)
    }
}
