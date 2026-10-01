import Foundation

/// The only persisted part of a device session. The access token stays in memory.
internal struct SessionCredentials: Codable, Equatable {
    let sessionSecret: String
    var verifiedUserId: String?
}
