import Foundation

public struct ReceptionPaywall: Sendable, Hashable {
    public let id: String
    public let title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }

    internal static func validated(_ paywalls: [Self]) -> [Self] {
        var result: [Self] = []
        var ids: Set<String> = []
        for paywall in paywalls {
            let id = paywall.id.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = paywall.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard result.count < 20, (1...64).contains(id.utf16.count),
                  id.range(of: "^[A-Za-z0-9_.-]+$", options: .regularExpression) != nil,
                  (1...60).contains(title.utf16.count), ids.insert(id).inserted else {
                Log.debug("Invalid or duplicate paywall dropped")
                continue
            }
            result.append(Self(id: id, title: title))
        }
        return result
    }
}
