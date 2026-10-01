import Foundation

internal struct Conversation: Decodable {
    let id: String
    let status: String
    let unreadForUser: Int
    let createdAt: Date
}

/// A team member's first name and a short-lived photo URL, sent with replies while the app shows team photos.
internal struct TeamMember: Decodable, Equatable {
    let id: String
    let name: String
    let photoUrl: URL?
}

internal struct ConversationResponse: Decodable {
    struct Device: Decodable { let blocked: Bool?; let verificationRequired: Bool? }
    struct Limits: Decodable {
        private let messages: Int?
        private let uploads: Int?
        private enum CodingKeys: CodingKey { case messages, uploads }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            messages = try? values.decode(Int.self, forKey: .messages)
            uploads = try? values.decode(Int.self, forKey: .uploads)
        }

        func seconds(for scope: RetryScope) -> Int? {
            let value = scope == .messages ? messages : scope == .uploads ? uploads : nil
            guard let value, (0...ReceptionAPI.maximumRetryAfter).contains(value) else { return nil }
            return value
        }
    }
    let limits: Limits?
    let boundedRead: Bool?
    let device: Device?
    let conversation: Conversation?
    let messages: [Message]
    let team: [TeamMember]?
}
internal struct ConversationState: Decodable { let id: String?; let status: String }
internal struct MessagesResponse: Decodable {
    let device: ConversationResponse.Device?
    let boundedRead: Bool?
    let conversation: ConversationState?
    let messages: [Message]
    let team: [TeamMember]?
    let hasMore: Bool?
}
internal struct SendResponse: Decodable { let conversation: Conversation; let message: Message }
internal struct EmptyResponse: Decodable {}
