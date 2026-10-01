import SwiftUI

internal struct ComposerDimensions: DynamicProperty {
    @ScaledMetric(relativeTo: .body) private var scale = Theme.unit

    func resolve(width: CGFloat, keyboard: Bool) -> Values {
        let base = Theme.composer
        // Keep usable text width when AX scaling would make the controls exceed a phone's width.
        let budget = base.restingMargin * 2 + base.plus + base.spacing + base.textLeading
            + base.sendWidth + base.sendInset + Theme.small + Theme.composerMinimumTextWidth
        let horizontal = min(scale, width / budget)
        return Values(scale: scale, horizontal: horizontal, keyboard: keyboard)
    }

    struct Values {
        let scale: CGFloat
        let horizontal: CGFloat
        let keyboard: Bool
        private var base: Theme.ComposerMetrics { Theme.composer }
        var textSize: CGFloat { Theme.bodySize * scale }
        var lineHeight: CGFloat { Theme.composerLineHeight * scale }
        var height: CGFloat { base.height * scale }
        var photo: CGFloat { base.plus * horizontal }
        var photoIcon: CGFloat { Theme.composerPhotoIcon * horizontal }
        var sendWidth: CGFloat { base.sendWidth * horizontal }
        var sendHeight: CGFloat { base.sendHeight * horizontal }
        var sendIcon: CGFloat { Theme.composerSendIcon * horizontal }
        var vertical: CGFloat { base.verticalInset * scale }
        var innerHeight: CGFloat { height - vertical * 2 }
        var leading: CGFloat { (keyboard ? base.leading : base.restingMargin) * horizontal }
        var trailing: CGFloat {
            if #available(iOS 26, *), !keyboard { return base.restingMargin * horizontal }
            return base.trailing * horizontal
        }
        var bottom: CGFloat { (keyboard ? base.keyboardGap : base.restingBottom) * scale }
        var gap: CGFloat { base.spacing * horizontal }
        var small: CGFloat { Theme.small * horizontal }
        var textLeading: CGFloat { base.textLeading * horizontal }
        var sendInset: CGFloat { base.sendInset * horizontal }
        var radius: CGFloat { Theme.composerMultilineRadius * scale }
        var chip: CGFloat { Theme.chip * horizontal }
        func buttonBottom(_ diameter: CGFloat, multiline: Bool) -> CGFloat {
            ((multiline ? lineHeight : innerHeight) - diameter) / 2
        }
    }
}
