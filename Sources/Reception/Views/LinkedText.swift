import SwiftUI

/// Message text with its web addresses tappable. Only `http` and `https` are linked; other schemes stay plain text.
@MainActor
internal enum LinkedText {
    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    static func attributed(_ text: String) -> AttributedString {
        var result = AttributedString(text)
        guard let detector else { return result }
        for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let url = match.url, ["http", "https"].contains(url.scheme?.lowercased()),
                  let range = Range(match.range, in: text), let linked = Range(range, in: result) else { continue }
            result[linked][AttributeScopes.FoundationAttributes.LinkAttribute.self] = url
            result[linked].swiftUI.underlineStyle = .single
        }
        return result
    }
}
