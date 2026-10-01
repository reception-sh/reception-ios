import SwiftUI

internal struct ImageLightbox: View {
    let attachment: Attachment
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = Theme.minimumZoom
    @GestureState private var magnification: CGFloat = Theme.minimumZoom

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Theme.lightboxBackground.ignoresSafeArea()
            GeometryReader { geometry in
                ScrollView([.horizontal, .vertical]) {
                    RemoteAttachmentImage(attachment: attachment, fills: false)
                    .frame(width: geometry.size.width * max(Theme.minimumZoom, min(Theme.maximumZoom, scale * magnification)),
                           height: geometry.size.height * max(Theme.minimumZoom, min(Theme.maximumZoom, scale * magnification)))
                    .gesture(MagnifyGesture().updating($magnification) { value, state, _ in
                        state = value.magnification
                    }.onEnded { scale = max(Theme.minimumZoom, min(Theme.maximumZoom, scale * $0.magnification)) })
                    .onTapGesture(count: 2) { scale = scale > Theme.minimumZoom ? Theme.minimumZoom : Theme.doubleTapZoom }
                }
            }
            DismissButton(lightbox: true) { dismiss() }
            .padding(Theme.spacing)
        }
        // Keep the photo controls dark without changing the presenting chat's appearance.
        .environment(\.colorScheme, .dark)
    }
}
