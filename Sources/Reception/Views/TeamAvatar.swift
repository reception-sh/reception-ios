import SwiftUI

/// A reply author's photo, or their initial while it loads or when they have none.
internal struct TeamAvatar: View {
    let member: TeamMember
    @ScaledMetric(relativeTo: .body) private var size = Theme.avatarSize

    var body: some View {
        AsyncImage(url: member.photoUrl) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                Text(member.name.prefix(1).uppercased())
                    .font(Theme.captionFont.weight(.semibold))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}
