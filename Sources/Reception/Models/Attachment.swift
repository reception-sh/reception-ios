import Foundation

internal struct Attachment: Codable, Identifiable {
    let id: String
    let url: URL
    let contentType: String
    let width: Int?
    let height: Int?
}
