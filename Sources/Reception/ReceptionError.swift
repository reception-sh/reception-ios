import Foundation

/// A failed server request from `Reception.shared.deleteData()`, where local data is retained for retrying,
/// or an identity token the service rejected (see `ReceptionEvent.identityRejected`).
public struct ReceptionError: Error, Hashable, Sendable {
    public let code: String
    /// HTTP status, or zero when no valid response was received.
    public let status: Int
}
