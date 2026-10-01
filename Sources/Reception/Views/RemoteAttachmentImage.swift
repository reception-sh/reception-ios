import SwiftUI

internal struct RemoteAttachmentImage: View {
    @State private var loader: AttachmentImageLoader?
    let fills: Bool
    var openPhoto: (() -> Void)?

    init(attachment: Attachment, fills: Bool, openPhoto: (() -> Void)? = nil) {
        let session = Reception.shared.session
        _loader = State(initialValue: session.map { $0.attachmentImages.loader(for: attachment, session: $0) })
        self.fills = fills
        self.openPhoto = openPhoto
    }

    var body: some View {
        Group {
            if loader?.failed == true {
                Button { loader?.retry() } label: {
                    VStack(spacing: Theme.small) {
                        Image(systemName: "exclamationmark.circle")
                        Text(Theme.string("Retry"))
                    }
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.imagePlaceholder)
                }.buttonStyle(.plain)
            } else if let openPhoto {
                Button(action: openPhoto) { photo }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Theme.string("Open photo"))
            } else {
                photo.accessibilityLabel(Theme.string("Photo"))
            }
        }
        .onAppear { loader?.appear() }
        .onDisappear { loader?.disappear() }
    }

    private var photo: some View {
        Group {
            if let image = loader?.image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: fills ? .fill : .fit)
            } else {
                Theme.imagePlaceholder.overlay {
                    if loader?.loading == true { ProgressView() }
                }
            }
        }
    }
}
