import SwiftUI

internal struct MessageImage: View {
    var attachment: Attachment?
    var image: UIImage?
    let maximumWidth: CGFloat
    var openPhoto: (() -> Void)?

    private var size: CGSize {
        let ratio: CGFloat
        if let width = attachment?.width, let height = attachment?.height, width > 0, height > 0 {
            ratio = CGFloat(width) / CGFloat(height)
        } else if let image, image.size.width > Theme.zero, image.size.height > Theme.zero {
            ratio = image.size.width / image.size.height
        } else {
            ratio = Theme.unit
        }
        let fittedWidth = min(maximumWidth, Theme.imageMaximumHeight * ratio)
        return CGSize(width: fittedWidth, height: fittedWidth / ratio)
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
                    .accessibilityLabel(Theme.string("Photo"))
            } else if let attachment {
                RemoteAttachmentImage(attachment: attachment, fills: true, openPhoto: openPhoto)
            } else {
                Theme.imagePlaceholder
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: Theme.bubbleRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.bubbleRadius, style: .continuous)
                .strokeBorder(Theme.imageBorder, lineWidth: Theme.imageBorderWidth)
                .allowsHitTesting(false)
        }
    }
}
