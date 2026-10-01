import SwiftUI

/// A remote icon choice: an SF Symbol, an uploaded image, or nothing.
internal enum AppearanceIcon: Equatable {
    case symbol(String)
    case image(URL)
    case hidden
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
        case .hidden:
            EmptyView()
        }
    }
}
