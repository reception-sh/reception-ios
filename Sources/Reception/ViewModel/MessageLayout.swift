import SwiftUI

internal struct MessageLayout {
    let showsDeliveryStatus: Bool
    let showsTimestamp: Bool
    let olderOutgoingCount: Int
    let spacing: CGFloat
    /// Set for agent replies whose author is known while the app shows team names or photos.
    var author: TeamMember?
    var authorPhoto: UIImage?
    var showsAuthorName = false
    var showsAuthorPhoto = false
    /// Reserve space even before team details arrive, keeping cached replies aligned.
    var reservesPhotoColumn = false
}

extension ChatModel {
    func messageLayout(at index: Int) -> MessageLayout {
        guard messages.indices.contains(index) else {
            return MessageLayout(showsDeliveryStatus: false, showsTimestamp: false, olderOutgoingCount: 0, spacing: Theme.zero)
        }
        let message = messages[index]
        let previous = index > 0 ? messages[index - 1] : nil
        let startsGroup = previous.map { !sameGroup($0, message) } ?? true
        let next = messages.indices.contains(index + 1) ? messages[index + 1] : nil
        let appearance = Reception.resolvedAppearance
        let showsAuthors = appearance.showsTeamNames || appearance.showsTeamPhotos
        let author = message.sender == "USER" || !showsAuthors ? nil : message.authorId.flatMap { team[$0] ?? teamProfiles.members[$0] }
        let reservesPhotoColumn = message.sender == "AGENT" && appearance.showsTeamPhotos
        return MessageLayout(
            showsDeliveryStatus: index == messages.lastIndex(where: { $0.sender == "USER" }),
            showsTimestamp: startsGroup && (previous.map {
                message.createdAt.timeIntervalSince($0.createdAt) > Theme.timestampInterval
            } ?? true),
            olderOutgoingCount: messages.dropFirst(index + 1).filter {
                $0.sender == "USER" && !$0.text.isEmpty
            }.count,
            spacing: previous == nil ? Theme.zero : (startsGroup ? Theme.groupSpacing : Theme.groupedSpacing),
            author: author,
            authorPhoto: appearance.showsTeamPhotos ? message.authorId.flatMap { teamProfiles.images[$0] } : nil,
            showsAuthorName: author != nil && appearance.showsTeamNames && startsGroup,
            showsAuthorPhoto: author != nil && reservesPhotoColumn && (next.map { !sameGroup(message, $0) } ?? true),
            reservesPhotoColumn: reservesPhotoColumn
        )
    }

    private func sameGroup(_ first: Message, _ second: Message) -> Bool {
        first.sender == second.sender && first.authorId == second.authorId && Calendar.current.isDate(
            first.createdAt, equalTo: second.createdAt, toGranularity: .minute
        )
    }
}
