import Foundation
import UIKit

internal struct Message: Identifiable {
    var id: String
    var clientId: String?
    var seq: Int64?
    let sender: String
    let text: String
    var attachments: [Attachment]
    let createdAt: Date
    var kind: String = "TEXT"
    var reviewUrl: URL?
    var paywallId: String?
    var paywallTitle: String?
    /// Agent-chosen button text; nil shows the localized default.
    var buttonLabel: String?
    /// Team member who wrote an agent reply; set only while the app shows team photos.
    var authorId: String?
    var actionClickedAt: Date?
    var status: MessageStatus = .sent
    var showsPending = false
    /// Timer expiry alone cannot resend this message.
    var awaitsManualRetry = false
    /// A verified early release may resume this submitted message. Explicit Cancel removes that permission.
    var retryAfterLimitRelease = false
    /// A submitted transport/server failure may resume after reopening, unless explicitly canceled.
    var retryAfterTransientFailure = false
    /// The wait that held this message's last attempt; in memory only, so it never outlives the process.
    var heldBy: RetryScope?
    var images: [UIImage] = []
    var attachmentIds: [String] = []
    // Retain the photo count even when a cached JPEG cannot be decoded.
    var expectedImageCount: Int?
    var hasConfirmedAttachments: Bool { seq != nil && !attachments.isEmpty }
}

extension Message: Decodable {
    private enum CodingKeys: String, CodingKey { case id, clientId, seq, sender, text, attachments, createdAt, kind, reviewUrl, paywallId, paywallTitle, buttonLabel, authorId, actionClickedAt }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        clientId = try values.decodeIfPresent(String.self, forKey: .clientId)
        seq = try values.decode(Int64.self, forKey: .seq)
        sender = try values.decode(String.self, forKey: .sender)
        text = try values.decode(String.self, forKey: .text)
        attachments = try values.decode([Attachment].self, forKey: .attachments)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        kind = try values.decodeIfPresent(String.self, forKey: .kind) ?? "TEXT"
        paywallId = try values.decodeIfPresent(String.self, forKey: .paywallId)
        paywallTitle = try values.decodeIfPresent(String.self, forKey: .paywallTitle)
        buttonLabel = try values.decodeIfPresent(String.self, forKey: .buttonLabel)
        authorId = try values.decodeIfPresent(String.self, forKey: .authorId)
        actionClickedAt = try values.decodeIfPresent(Date.self, forKey: .actionClickedAt)
        reviewUrl = try values.decodeIfPresent(URL.self, forKey: .reviewUrl)
    }
}
