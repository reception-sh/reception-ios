import SwiftUI

@MainActor
internal enum ReceptionLocalization {
    static var appLanguage: String {
        canonical(Reception.shared.languageOverride ?? Bundle.main.preferredLocalizations.first ?? "en")
    }
    static var language: String { resolveLanguage(appLanguage) }
    static var locale: Locale { Locale(identifier: language) }
    static var layoutDirection: LayoutDirection {
        ["ar", "he", "ur"].contains(language) ? .rightToLeft : .leftToRight
    }
    static var bundle: Bundle {
        guard let url = Bundle.module.url(forResource: language, withExtension: "lproj"),
              let bundle = Bundle(url: url) else { return englishBundle }
        return bundle
    }
    private static var englishBundle: Bundle {
        guard let url = Bundle.module.url(forResource: "en", withExtension: "lproj"),
              let bundle = Bundle(url: url) else { return .module }
        return bundle
    }

    nonisolated static let supportedLanguages = [
        "en", "de", "fr", "fr-CA", "es", "es-419", "it", "pt-BR", "pt-PT", "ca", "ro", "nl",
        "sv", "da", "nb", "fi", "pl", "cs", "sk", "hu", "sl", "hr", "el", "uk", "ru", "tr",
        "ja", "ko", "zh-Hans", "zh-Hant", "zh-HK", "th", "vi", "id", "ms", "hi", "bn", "gu",
        "kn", "ml", "mr", "or", "pa", "ta", "te", "ur", "ar", "he"
    ]

    nonisolated static func canonical(_ identifier: String) -> String {
        let value = identifier.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "_", with: "-")
        let pattern = "^([A-Za-z]{2,3}|[A-Za-z]{5,8})(-[A-Za-z]{4})?(-([A-Za-z]{2}|[0-9]{3}))?"
            + "(-([A-Za-z0-9]{5,8}|[0-9][A-Za-z0-9]{3}))*"
            + "(-[0-9A-WY-Za-wy-z](-[A-Za-z0-9]{2,8})+)*(-[xX](-[A-Za-z0-9]{1,8})+)?$"
        guard value.range(of: pattern, options: .regularExpression) != nil else { return "en" }
        var variants = Set<String>()
        var extensions = Set<String>()
        var inExtension = false
        for part in value.lowercased().split(separator: "-").dropFirst() {
            if part == "x" { break }
            if part.count == 1 {
                guard extensions.insert(String(part)).inserted else { return "en" }
                inExtension = true
            } else if !inExtension, part.count >= 5 || (part.count == 4 && part.first?.isNumber == true) {
                guard variants.insert(String(part)).inserted else { return "en" }
            }
        }
        var components = Locale.canonicalLanguageIdentifier(from: value).split(separator: "-").map(String.init)
        // Foundation retains this retired code on some OS versions; the backend uses its modern alias.
        if components.first == "mo" { components[0] = "ro" }
        let base = components.prefix { $0.count != 1 }.joined(separator: "-")
        return base.isEmpty || base.utf16.count > 35 ? "en" : base
    }

    nonisolated static func resolveLanguage(_ identifier: String) -> String {
        let tag = canonical(identifier)
        if let exact = supportedLanguages.first(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) { return exact }
        let parts = tag.split(separator: "-").map(String.init)
        let language = parts.first?.lowercased() ?? "en"
        let script = parts.dropFirst().first { $0.count == 4 }?.lowercased()
        let region = parts.dropFirst().first { $0.count == 2 || ($0.count == 3 && $0.allSatisfy(\.isNumber)) }?.uppercased()
        switch language {
        case "zh":
            if script == "hans" { return "zh-Hans" }
            if region == "HK" || region == "MO" { return "zh-HK" }
            return script == "hant" || region == "TW" ? "zh-Hant" : "zh-Hans"
        case "es": return region == nil || region == "ES" ? "es" : "es-419"
        case "pt": return region == "PT" ? "pt-PT" : "pt-BR"
        case "fr": return region == "CA" ? "fr-CA" : "fr"
        case "no", "nn", "nb": return "nb"
        default: return supportedLanguages.contains(language) ? language : "en"
        }
    }
}
