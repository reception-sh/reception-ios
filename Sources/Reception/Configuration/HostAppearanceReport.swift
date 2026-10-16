import SwiftUI

/// The host's own appearance in the dashboard's schema, sent with device registration and updates so the
/// dashboard editor can start from what the app sets in code. It lists only values that differ from
/// `Appearance()`, plus the app's accent color; bundled images are reported as present, never uploaded.
@MainActor
internal enum HostAppearanceReport {
    static func payload(_ appearance: Reception.Appearance, usesRemoteAppearance: Bool) -> [String: Any] {
        var report: [String: Any] = ["usesRemoteAppearance": usesRemoteAppearance]
        var colors: [String: Any] = [:]
        colors["accent"] = appearance.accentColor == .accentColor ? assetAccent() : pair(appearance.accentColor)
        colors["onAccent"] = appearance.onAccentColor.flatMap(pair)
        colors["background"] = appearance.chatBackground.flatMap(pair)
        colors["incoming"] = appearance.incomingBackground.flatMap(pair)
        colors["incomingText"] = appearance.incomingForeground.flatMap(pair)
        if !colors.isEmpty { report["colors"] = colors }
        var text: [String: String] = [:]
        text["title"] = appearance.titleOverride
        text["welcomeTitle"] = appearance.welcomeTitleOverride
        text["welcomeText"] = appearance.welcomeTextOverride
        if !text.isEmpty { report["text"] = text }
        switch appearance.preferredColorScheme {
        case .light: report["colorScheme"] = "light"
        case .dark: report["colorScheme"] = "dark"
        default: break
        }
        if appearance.showsCloseButton { report["showsCloseButton"] = true }
        if appearance.closeIcon != .xmark { report["closeIcon"] = appearance.closeIcon.rawValue }
        if appearance.closeImage != nil { report["closeImage"] = true }
        if let design = appearance.fontDesign.flatMap(designName) { report["fontDesign"] = design }
        report["fontFamily"] = appearance.fontFamily
        if !appearance.fadesOlderMessages { report["fadesOlderMessages"] = false }
        let icon = welcomeIcon(appearance)
        if !icon.isEmpty { report["welcomeIcon"] = icon }
        var visibility: [String: Bool] = [:]
        if appearance.hidesTitle { visibility["title"] = false }
        if appearance.hidesWelcomeTitle { visibility["welcomeTitle"] = false }
        if appearance.hidesWelcomeText { visibility["welcomeText"] = false }
        if appearance.welcomeIcon?.icon.isHidden == true { visibility["welcomeIcon"] = false }
        if !visibility.isEmpty { report["visibility"] = visibility }
        return report
    }

    private static func welcomeIcon(_ appearance: Reception.Appearance) -> [String: Any] {
        var icon: [String: Any] = [:]
        switch appearance.welcomeIcon?.icon {
        case .symbol(let name): icon["symbol"] = name
        case .local, .image: icon["image"] = true
        case .hidden, nil: break
        }
        icon["color"] = appearance.welcomeIconColor.flatMap(pair)
        icon["size"] = appearance.welcomeIconSize.map { Int($0.rounded()) }
        if appearance.welcomeIconCornerRadius != 0 { icon["cornerRadius"] = Int(appearance.welcomeIconCornerRadius.rounded()) }
        if appearance.welcomeIconOffset != .zero {
            icon["offset"] = ["x": Int(appearance.welcomeIconOffset.width.rounded()), "y": Int(appearance.welcomeIconOffset.height.rounded())]
        }
        return icon
    }

    /// The default accent comes from the app's asset catalog; without one the SDK uses the system blue the editor shows anyway.
    private static func assetAccent() -> [String: String]? {
        let name = Bundle.main.object(forInfoDictionaryKey: "NSAccentColorName") as? String ?? "AccentColor"
        return UIColor(named: name).flatMap { pair(Color(uiColor: $0)) }
    }

    /// Light and dark variants as opaque `#RRGGBB`, the only form the dashboard accepts.
    static func pair(_ color: Color) -> [String: String]? {
        let dynamic = UIColor(color)
        guard let light = hex(dynamic, .light), let dark = hex(dynamic, .dark) else { return nil }
        return ["light": light, "dark": dark]
    }

    private static func hex(_ color: UIColor, _ style: UIUserInterfaceStyle) -> String? {
        let resolved = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: style)).cgColor
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let components = resolved.converted(to: space, intent: .defaultIntent, options: nil)?.components,
              components.count >= 3 else { return nil }
        let channels = components.prefix(3).map { Int((min(max($0, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", channels[0], channels[1], channels[2])
    }

    private static func designName(_ design: Font.Design) -> String? {
        switch design {
        case .default: "default"
        case .rounded: "rounded"
        case .serif: "serif"
        case .monospaced: "monospaced"
        @unknown default: nil
        }
    }
}
