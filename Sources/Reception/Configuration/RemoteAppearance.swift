import SwiftUI

internal struct AppearanceEnvelope: Codable {
    let schemaVersion: Int
    let revision: Int
    let appearance: RemoteAppearance
}

internal struct RemoteAppearance: Codable {
    var colors: [String: AdaptiveAppearanceColor]?
    var text: [String: [String: String]]?
    var colorScheme: String?
    var showsCloseButton: Bool?
    var closeIcon: String?
    var closeImage: String?
    var hidden: [String]?
    var visibility: [String: Bool]?
    var fontDesign: String?
    var fadesOlderMessages: Bool?
    var showsTeamPhotos: Bool?
    var showsTeamNames: Bool?
    var welcomeIcon: RemoteIcon?
    var cards: RemoteCards?

    struct RemoteIcon: Codable {
        var symbol: String?
        var image: String?
        var color: AdaptiveAppearanceColor?
        var size: Double?
        var offset: RemoteOffset?
    }
    struct RemoteOffset: Codable { var x: Double; var y: Double }
    struct RemoteCards: Codable { var review: RemoteCard?; var offer: RemoteCard? }
    struct RemoteCard: Codable {
        var icon: String?
        var iconImage: String?
        var accessory: String?
        var accessoryImage: String?
        var button: AdaptiveAppearanceColor?
        var buttonText: AdaptiveAppearanceColor?
        var iconSize: Double?

        @MainActor
        func style(accent: Color, onAccent: Color, hidesIcon: Bool?, hidesAccessory: Bool?) -> Reception.Appearance.CardStyle {
            .init(icon: RemoteAppearance.icon(symbol: icon, image: iconImage, hidden: hidesIcon),
                  accessory: RemoteAppearance.icon(symbol: accessory, image: accessoryImage, hidden: hidesAccessory),
                  button: button?.color(fallback: accent), buttonText: buttonText?.color(fallback: onAccent),
                  iconSize: iconSize.map { CGFloat(min(max($0, 8), 28)) })
        }
    }

    /// Explicit visibility overrides legacy "none"; images take precedence over symbols.
    @MainActor
    static func icon(symbol: String?, image: String?, hidden: Bool?) -> AppearanceIcon? {
        if hidden == true || (hidden == nil && symbol == "none") { return .hidden }
        if let image, let url = Reception.shared.appearanceImageURL(image) { return .image(url) }
        if let symbol, UIImage(systemName: symbol) != nil { return .symbol(symbol) }
        return nil
    }

    @MainActor
    func applying(to local: Reception.Appearance) -> Reception.Appearance {
        var result = local
        result.accentColor = colors?["accent"]?.color(fallback: local.accentColor) ?? local.accentColor
        result.onAccentColor = colors?["onAccent"]?.color(fallback: local.onAccentColor ?? .white) ?? local.onAccentColor
        result.chatBackground = colors?["background"]?.color(fallback: local.chatBackground ?? Color(uiColor: .systemBackground)) ?? local.chatBackground
        result.incomingBackground = colors?["incoming"]?.color(fallback: local.incomingBackground ?? Color(uiColor: .secondarySystemBackground)) ?? local.incomingBackground
        result.incomingForeground = colors?["incomingText"]?.color(fallback: local.incomingForeground ?? .primary) ?? local.incomingForeground
        result.title = localized("title", maximum: 80) ?? local.title
        result.welcomeTitle = localized("welcomeTitle", maximum: 160) ?? local.welcomeTitle
        result.welcomeText = localized("welcomeText", maximum: 1000) ?? local.welcomeText
        result.showsCloseButton = showsCloseButton ?? local.showsCloseButton
        if let closeIcon, let icon = Reception.CloseIcon(rawValue: closeIcon) {
            result.closeIcon = icon
            result.closeImage = nil
        }
        switch colorScheme {
        case "system": result.preferredColorScheme = nil
        case "light": result.preferredColorScheme = .light
        case "dark": result.preferredColorScheme = .dark
        default: break
        }
        if let design = systemFontDesign {
            result.fontDesign = design
            result.fontFamily = nil
        }
        result.fadesOlderMessages = fadesOlderMessages ?? local.fadesOlderMessages
        result.showsTeamPhotos = showsTeamPhotos ?? false
        result.showsTeamNames = showsTeamNames ?? false
        result.hidesTitle = isHidden("title") ?? local.hidesTitle
        result.hidesWelcomeTitle = isHidden("welcomeTitle") ?? local.hidesWelcomeTitle
        result.hidesWelcomeText = isHidden("welcomeText") ?? local.hidesWelcomeText
        let hidesWelcomeIcon = isHidden("welcomeIcon")
        let localIcon = hidesWelcomeIcon == false && local.welcomeIcon?.icon.isHidden == true ? nil : local.welcomeIcon
        result.welcomeIcon = Self.icon(symbol: welcomeIcon?.symbol, image: welcomeIcon?.image, hidden: hidesWelcomeIcon)
            .map(Reception.WelcomeIcon.init(icon:)) ?? localIcon
        result.welcomeIconColor = welcomeIcon?.color?.color(fallback: local.welcomeIconColor ?? Color(uiColor: .tertiaryLabel))
            ?? local.welcomeIconColor
        result.welcomeIconSize = welcomeIcon?.size.map { CGFloat(min(max($0, 16), 160)) } ?? local.welcomeIconSize
        if let offset = welcomeIcon?.offset {
            result.welcomeIconOffset = CGSize(width: min(max(offset.x, -120), 120), height: min(max(offset.y, -120), 120))
        }
        result.remoteCloseImage = closeImage.flatMap { Reception.shared.appearanceImageURL($0) }
        let accent = result.accentColor, onAccent = result.onAccentColor ?? .white
        result.reviewCard = (cards?.review ?? RemoteCard()).style(accent: accent, onAccent: onAccent,
            hidesIcon: isHidden("reviewIcon"), hidesAccessory: isHidden("reviewAccessory"))
        result.offerCard = (cards?.offer ?? RemoteCard()).style(accent: accent, onAccent: onAccent,
            hidesIcon: isHidden("offerIcon"), hidesAccessory: isHidden("offerAccessory"))
        return result
    }

    private func isHidden(_ element: String) -> Bool? {
        if let visible = visibility?[element] { return !visible }
        return hidden?.contains(element) == true ? true : nil
    }

    private var systemFontDesign: Font.Design? {
        switch fontDesign {
        case "default": return .default
        case "rounded": return .rounded
        case "serif": return .serif
        case "monospaced": return .monospaced
        default: return nil
        }
    }

    @MainActor
    private func localized(_ key: String, maximum: Int) -> String? {
        guard let translations = text?[key] else { return nil }
        for language in [ReceptionLocalization.appLanguage, ReceptionLocalization.language] {
            if let value = translations.first(where: { $0.key.caseInsensitiveCompare(language) == .orderedSame })?.value,
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, value.utf16.count <= maximum {
                return value
            }
        }
        return nil
    }
}
