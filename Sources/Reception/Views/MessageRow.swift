import SwiftUI

internal struct MessageRow: View {
    let message: Message
    let availableWidth: CGFloat
    let layout: MessageLayout
    let openReview: (URL, OpenURLAction) -> Void
    let canOpenPaywall: Bool
    let openPaywall: () -> Void
    let retryAvailability: RetryAvailability
    let cancelRetry: () -> Void
    let retry: () -> Void
    @ScaledMetric(relativeTo: .body) private var avatarSize = Theme.avatarSize

    var body: some View {
        VStack(spacing: Theme.small) {
            if layout.showsTimestamp {
                Text(message.createdAt, format: .dateTime.weekday(.abbreviated).hour().minute())
                    .font(Theme.timestampFont).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity)
            }
            if let author = layout.author {
                VStack(alignment: .leading, spacing: Theme.authorNameSpacing) {
                    if layout.showsAuthorName {
                        Text(author.name)
                            .font(Theme.timestampFont).foregroundStyle(Theme.muted)
                            .padding(.leading, (layout.reservesPhotoColumn ? avatarSize + Theme.small : Theme.zero) + Theme.bubbleHorizontal)
                    }
                    if layout.reservesPhotoColumn {
                        HStack(alignment: .bottom, spacing: Theme.small) {
                            if layout.showsAuthorPhoto { TeamAvatar(member: author) }
                            else { Color.clear.frame(width: avatarSize, height: Theme.zero) }
                            bubble(width: availableWidth - avatarSize - Theme.small)
                        }
                    } else {
                        bubble(width: availableWidth)
                    }
                }
            } else {
                bubble(width: availableWidth)
            }
        }
        .padding(.top, layout.spacing)
    }

    private func bubble(width: CGFloat) -> some View {
        MessageBubble(message: message, availableWidth: width, showsDeliveryStatus: layout.showsDeliveryStatus, olderOutgoingCount: layout.olderOutgoingCount, openReview: openReview, canOpenPaywall: canOpenPaywall, openPaywall: openPaywall, retryAvailability: retryAvailability, cancelRetry: cancelRetry, retry: retry)
    }
}
