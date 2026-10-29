import Foundation

/// Which link card URLs the chat opens, and which of them lead back into the host app.
internal struct LinkPolicy {
    /// The host's own URL schemes from `CFBundleURLTypes` in `Info.plist` order, lowercased, each once.
    let hostSchemes: [String]

    init(infoDictionary: [String: Any]?) {
        let types = infoDictionary?["CFBundleURLTypes"] as? [[String: Any]] ?? []
        var seen = Set<String>()
        hostSchemes = types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
            .map { $0.lowercased() }
            .filter { $0.count <= 64 && Self.isSchemeName($0) && seen.insert($0).inserted }
    }

    func isHostScheme(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return hostSchemes.contains(scheme)
    }

    /// Read once from the host app; tests replace it.
    @MainActor static var main = LinkPolicy(infoDictionary: Bundle.main.infoDictionary)
    private static let systemSchemes: Set<String> = ["https", "http", "mailto", "tel", "sms"]
    private static let blockedSchemes: Set<String> = ["javascript", "data", "file", "blob", "about", "vbscript"]

    /// The service applies the same rule when a link is saved; this check only guards against unexpected data.
    static func isAllowed(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        if systemSchemes.contains(scheme) { return true }
        return !blockedSchemes.contains(scheme) && isSchemeName(scheme)
    }

    /// A web page the chat can show in Safari. App Store links stay with the system so the App Store opens them.
    static func isWebLink(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host?.lowercased(), !host.isEmpty else { return false }
        return !appStoreHosts.contains(host) && !host.hasSuffix(".apps.apple.com")
    }

    private static let appStoreHosts: Set<String> = ["apps.apple.com", "itunes.apple.com"]

    private static func isSchemeName(_ scheme: String) -> Bool {
        scheme.range(of: "^[a-z][a-z0-9+.-]*$", options: .regularExpression) != nil
    }
}
