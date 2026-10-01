import SwiftUI

internal struct AdaptiveAppearanceColor: Codable {
    let light: String?
    let dark: String?

    func color(fallback: Color) -> Color? {
        let lightColor = light.flatMap(Self.parse)
        let darkColor = dark.flatMap(Self.parse)
        guard lightColor != nil || darkColor != nil else { return nil }
        let fallbackColor = UIColor(fallback)
        return Color(uiColor: UIColor { traits in
            (traits.userInterfaceStyle == .dark ? darkColor : lightColor)
                ?? fallbackColor.resolvedColor(with: traits)
        })
    }

    private static func parse(_ value: String) -> UIColor? {
        guard value.count == 7, value.first == "#", let hex = UInt32(value.dropFirst(), radix: 16) else { return nil }
        return UIColor(red: CGFloat((hex >> 16) & 255) / 255,
                       green: CGFloat((hex >> 8) & 255) / 255,
                       blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
}
