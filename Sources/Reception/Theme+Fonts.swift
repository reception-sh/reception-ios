import SwiftUI

extension Theme {
    @MainActor static func textFont(
        size: CGFloat, scaledSize: CGFloat? = nil, relativeTo style: Font.TextStyle = .body,
        weight: Font.Weight = .regular
    ) -> Font {
        let appearance = Reception.resolvedAppearance
        if let family = appearance.fontFamily {
            // Custom fonts scale themselves; ScaledMetric sizes are only for system fonts.
            return .custom(family, size: size, relativeTo: style).weight(weight)
        }
        return .system(size: scaledSize ?? size, weight: weight, design: appearance.fontDesign ?? .default)
    }

    @MainActor private static func styledFont(
        _ style: Font.TextStyle, size: CGFloat, weight: Font.Weight = .regular
    ) -> Font {
        let appearance = Reception.resolvedAppearance
        if let family = appearance.fontFamily {
            return .custom(family, size: size, relativeTo: style).weight(weight)
        }
        return .system(style, design: appearance.fontDesign ?? .default)
    }

    @MainActor static var titleFont: Font { styledFont(.headline, size: 17, weight: .semibold) }
    @MainActor static var bodyFont: Font { styledFont(.body, size: bodySize) }
    @MainActor static var captionFont: Font { styledFont(.caption, size: 12) }
    @MainActor static var timestampFont: Font { styledFont(.caption2, size: 11) }
    @MainActor static var footnoteFont: Font { styledFont(.footnote, size: 13) }
    @MainActor static var dismissFont: Font {
        guard let family = Reception.resolvedAppearance.fontFamily else { return .system(size: 15, weight: .semibold) }
        return .custom(family, size: 15, relativeTo: .subheadline).weight(.semibold)
    }
    @MainActor static var closeFont: Font {
        guard let family = Reception.resolvedAppearance.fontFamily else { return .title2 }
        return .custom(family, size: 22, relativeTo: .title2)
    }
}
