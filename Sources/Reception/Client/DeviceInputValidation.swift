import Foundation

/// The service's limits in UTF-16 units. Over-limit host values are dropped instead of sent, because a rejected
/// registration or device update would block loading and sending.
internal enum DeviceInputValidation {
    static func checked(_ value: String?, field: String, limit: Int) -> String? {
        guard let value, value.utf16.count > limit else { return value }
        Log.error("identify: \(field) longer than \(limit) characters is not sent")
        return nil
    }

    static func checked(_ metadata: [String: String]) -> [String: String] {
        guard metadata.count <= 20 else {
            Log.error("setMetadata: more than 20 entries, no metadata is sent")
            return [:]
        }
        let accepted = metadata.filter { (1...64).contains($0.key.utf16.count) && $0.value.utf16.count <= 512 }
        if accepted.count < metadata.count {
            Log.error("setMetadata: entries need keys of 1 to 64 characters and values of up to 512; others are not sent")
        }
        return accepted
    }
}
