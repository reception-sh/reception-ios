import SwiftUI

internal struct ComposerSurface: ViewModifier {
    let multiline: Bool
    let radius: CGFloat
    @Environment(\.displayScale) private var displayScale

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content.background(.ultraThinMaterial, in: shape)
                .overlay { shape.stroke(Theme.separator, lineWidth: 1 / displayScale) }
        }
    }

    private var shape: AnyShape {
        multiline ? AnyShape(RoundedRectangle(cornerRadius: radius, style: .continuous)) : AnyShape(Capsule())
    }
}

internal struct ComposerButtonSurface: ViewModifier {
    @Environment(\.displayScale) private var displayScale

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(.regular.interactive(), in: .circle)
        } else {
            content.background(.ultraThinMaterial, in: Circle())
                .overlay { Circle().strokeBorder(Theme.separator, lineWidth: 1 / displayScale) }
        }
    }
}
