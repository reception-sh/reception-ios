import SwiftUI

/// Keeps a neutral placeholder until the author is known, then their initial until the photo loads.
internal struct TeamAvatar: View {
    let member: TeamMember?
    let image: UIImage?
    @ScaledMetric(relativeTo: .body) private var size = Theme.avatarSize

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Text(member.map { String($0.name.prefix(1)).uppercased() } ?? "")
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
