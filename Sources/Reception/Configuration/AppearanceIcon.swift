import SwiftUI

/// An icon choice: an SF Symbol, an uploaded image, an image from the host app, or nothing.
internal enum AppearanceIcon {
    case symbol(String)
    case image(URL)
    case local(Image)
    case hidden

    var isHidden: Bool { if case .hidden = self { true } else { false } }
}

/// Draws an icon at `size`; symbols take the surrounding foreground style, images keep their own colors.
internal struct AppearanceIconView: View {
    let icon: AppearanceIcon
    let size: CGFloat
    var weight: Font.Weight = .regular
    var imageCornerRadius: CGFloat = 0

    var body: some View {
        switch icon {
        case .symbol(let name):
            Image(systemName: name).font(.system(size: size, weight: weight))
        case .image(let url):
            AsyncImage(url: url) { image in
                imageContent(image)
            } placeholder: {
                Color.clear
            }
            .frame(width: size, height: size)
        case .local(let image):
            imageContent(image).frame(width: size, height: size)
        case .hidden:
            EmptyView()
        }
    }

    private func imageContent(_ image: Image) -> some View {
        image.resizable().renderingMode(.original).scaledToFit()
            // Clip the fitted image before adding its square layout frame.
            .clipShape(RoundedRectangle(cornerRadius: imageCornerRadius, style: .continuous))
    }
}
