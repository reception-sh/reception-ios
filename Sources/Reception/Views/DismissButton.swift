import SwiftUI

internal struct DismissButton: View {
    var lightbox = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            surface
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Theme.string("Close"))
    }

    private var glyph: some View {
        Group {
            if !lightbox, let url = Reception.resolvedAppearance.remoteCloseImage {
                AppearanceIconView(icon: .image(url), size: Theme.dismissImageSize)
            } else if !lightbox, let image = Reception.resolvedAppearance.closeImage {
                AppearanceIconView(icon: .local(image), size: Theme.dismissImageSize)
            } else {
                Image(systemName: lightbox ? "xmark" : Reception.resolvedAppearance.closeIcon.rawValue)
                    .imageScale(.medium)
                    .font(Theme.dismissFont)
            }
        }
        .frame(width: Theme.dismissDiameter, height: Theme.dismissDiameter)
        .contentShape(Circle())
    }

    @ViewBuilder private var surface: some View {
        if lightbox {
            glyph.foregroundStyle(Theme.lightboxForeground)
                .background(.regularMaterial, in: Circle())
        } else if #available(iOS 26, *) {
            glyph.foregroundStyle(Theme.foreground)
                .glassEffect(.regular.interactive(), in: .circle)
        } else {
            glyph.foregroundStyle(Theme.foreground)
                .background(Theme.dismissFill, in: Circle())
                .background(.ultraThinMaterial, in: Circle())
        }
    }
}
