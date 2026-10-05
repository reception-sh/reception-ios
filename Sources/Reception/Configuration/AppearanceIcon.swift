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

    var body: some View {
        switch icon {
        case .symbol(let name):
            Image(systemName: name).font(.system(size: size, weight: weight))
        case .image(let url):
            AsyncImage(url: url) { image in
                image.resizable().renderingMode(.original).scaledToFit()
            } placeholder: {
                Color.clear
            }
            .frame(width: size, height: size)
        case .local(let image):
            image.resizable().renderingMode(.original).scaledToFit().frame(width: size, height: size)
        case .hidden:
            EmptyView()
        }
    }
}
