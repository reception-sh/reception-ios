import SwiftUI

/// Message text with its web addresses tappable, in the bubble's own color like Messages. Only `http` and `https`
/// are linked; other schemes stay plain text.
internal enum LinkedText {
    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    static func attributed(_ text: String, linkColor: Color) -> AttributedString {
        var result = AttributedString(text)
        guard let detector else { return result }
        let attributes = AttributeContainer([.foregroundColor: UIColor(linkColor), .underlineStyle: NSUnderlineStyle.single.rawValue])
        for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let url = match.url, ["http", "https"].contains(url.scheme?.lowercased()),
                  let range = Range(match.range, in: text),
                  let start = AttributedString.Index(range.lowerBound, within: result),
                  let end = AttributedString.Index(range.upperBound, within: result) else { continue }
            result[start..<end].mergeAttributes(attributes.merging(AttributeContainer([.link: url])))
        }
        return result
    }
}
