import SwiftUI

internal enum Theme {
    static let zero: CGFloat = 0
    static let titleChipHorizontal: CGFloat = 16
    static let titleChipVertical: CGFloat = 8
    static let headerFadeHeight: CGFloat = 80
    static let headerFadeOverlap: CGFloat = 64
    static let sheetTopInset: CGFloat = 20
    static let layoutSettleDuration = 0.25
    static let deliveryStatusAnimation = Animation.easeOut(duration: 0.2)
    static let messageAnimation = Animation.easeOut(duration: 0.25)
    static let sendButtonAnimation = Animation.easeOut(duration: 0.2)
    static let uploadProgressHorizontalInset: CGFloat = 24
    static let sendingDotRestingOpacity = 0.35
    static let sendingDotOpacityRange = 0.65
    static let sendingOpacity = 0.6
    static let fullOpacity = 1.0
    static let failureIconSize: CGFloat = 20
    static let connectionSize: CGFloat = 13
    static let sendingDisabledSize: CGFloat = 13
    static let sendingDisabledLineLimit = 2
    static let sendingDisabledMinimumScale: CGFloat = 0.5
    static let sendingDisabledAnimation = Animation.easeInOut(duration: 0.2)
    static let connectionDotCount = 3
    static let connectionDotDiameter: CGFloat = 3
    static let connectionDotLift: CGFloat = 2
    static let connectionDotSpacing: CGFloat = 3
    static let connectionDotTextSpacing: CGFloat = 4
    static func connectionDotAnimation(index: Int) -> Animation {
        .easeInOut(duration: 0.6).repeatForever(autoreverses: true).delay(Double(index) * 0.2)
    }
    static let typingDotDiameter: CGFloat = 7
    static let typingDotSpacing: CGFloat = 4
    static let typingDotLift: CGFloat = 2
    static let typingFrameInterval = 1.0 / 30
    static let typingRestingOpacity = 0.45
    static let typingOpacityRange = 0.45
    static let typingRestingScale = 0.9
    static let typingScaleRange = 0.1
    static let typingCycleDuration = 1.5
    static let typingPulseDuration = 0.7
    static let typingStagger = 0.16
    static func typingPulse(elapsed: TimeInterval, index: Int) -> Double {
        let phase = (max(0, elapsed) + typingCycleDuration - Double(index) * typingStagger)
            .truncatingRemainder(dividingBy: typingCycleDuration)
        guard phase < typingPulseDuration else { return 0 }
        return sin(.pi * phase / typingPulseDuration)
    }

    static let connectedDuration = 3.0
    /// Countdowns tick together on whole seconds, so every wait on screen shows the same value.
    static var countdownTicks: PeriodicTimelineSchedule {
        .periodic(from: Date(timeIntervalSinceReferenceDate: Date.timeIntervalSinceReferenceDate.rounded(.down)), by: 1)
    }
    static let success = Color.green
    static let deliveryStatusSize: CGFloat = 12
    static let deliveryStatusSpacing: CGFloat = 2
    static let bubbleRadius: CGFloat = 16
    static let bubbleHorizontal: CGFloat = 14
    static let bubbleVertical: CGFloat = 10
    static let groupedSpacing: CGFloat = 2
    static let groupSpacing: CGFloat = 10
    static let timestampInterval: TimeInterval = 5 * 60
    struct ComposerMetrics {
        let height: CGFloat
        let plus: CGFloat
        let sendWidth: CGFloat
        let sendHeight: CGFloat
        let sendInset: CGFloat
        let textLeading: CGFloat
        let leading: CGFloat
        let trailing: CGFloat
        let restingMargin: CGFloat
        let keyboardGap: CGFloat
        let restingBottom: CGFloat
        let spacing: CGFloat
        var verticalInset: CGFloat { (height - sendHeight) / 2 }
    }
    // measured against Messages on iOS 26 (26.5, iPhone 17 Pro, 3×)
    static let composer26 = ComposerMetrics(
        height: 121 / 3, plus: 40, sendWidth: 38, sendHeight: 28,
        sendInset: 19 / 3, textLeading: 16, leading: 16, trailing: 16,
        restingMargin: 28, keyboardGap: 16, restingBottom: -6, spacing: 12)
    // measured against Messages on iOS 18 (18.2, iPhone 16 Pro, 3×)
    static let composer18 = ComposerMetrics(
        height: 37, plus: 34, sendWidth: 82 / 3, sendHeight: 82 / 3,
        sendInset: 14 / 3, textLeading: 13, leading: 14, trailing: 16,
        restingMargin: 14, keyboardGap: 14, restingBottom: 8, spacing: 12)
    static var composer: ComposerMetrics {
        if #available(iOS 26, *) { composer26 } else { composer18 }
    }
    static let composerMessageGap: CGFloat = 16
    static let composerMultilineRadius: CGFloat = 18
    static let composerLineLimit = 5
    static let unit: CGFloat = 1
    static let composerPhotoIcon: CGFloat = 18
    static let composerSendIcon: CGFloat = 15
    static let composerLineHeight: CGFloat = 21
    static let composerMinimumTextWidth: CGFloat = 120
    static let composerReferenceWidth: CGFloat = 402
    static let composerDisabled = Color.secondary.opacity(0.2)
    static let separator = Color(uiColor: .separator)
    static let bodySize: CGFloat = 17
    static let emptyIconSize: CGFloat = 44
    static let emptyTitleSize: CGFloat = 22
    static let emptySubtitleSize: CGFloat = 15
    static let emptyBottomInset: CGFloat = 48
    static let lightboxBackground = Color.black
    static let lightboxForeground = Color.white
    static let dismissDiameter: CGFloat = 44
    static let toolbarControlDiameter: CGFloat = 44
    // iOS 26 reserves a 20-pt toolbar margin; align the circle to our 16-pt edge.
    static let toolbarGlassCorrection: CGFloat = 4
    static let dismissFill = Color(uiColor: .secondarySystemFill)
    static let minimumZoom: CGFloat = 1
    static let maximumZoom: CGFloat = 5
    static let doubleTapZoom: CGFloat = 3
    static let small: CGFloat = 8
    static let spacing: CGFloat = 16
    static let radius: CGFloat = 22
    static let control: CGFloat = 48
    static let avatarSize: CGFloat = 28
    static let cardIconSize: CGFloat = 12
    static let dismissImageSize: CGFloat = 18
    static let authorNameSpacing: CGFloat = 4
    static let imageWidthFraction: CGFloat = 0.7
    static let imageMaximumHeight: CGFloat = 320
    static let imageBorder = Color.primary.opacity(0.12)
    static let imageBorderWidth: CGFloat = 0.5
    static let imagePlaceholder = Color(uiColor: .secondarySystemFill)
    static let chip: CGFloat = 56
    @MainActor static var background: Color { Reception.resolvedAppearance.chatBackground ?? Color(uiColor: .systemBackground) }
    @MainActor static var secondary: Color { Reception.resolvedAppearance.incomingBackground ?? Color(uiColor: .secondarySystemBackground) }

    static let outgoingText = Color.white
    static let outgoingFadeStep = 0.06
    static let outgoingMaximumFade = 0.24

    @MainActor
    static var outgoingForeground: Color { Reception.resolvedAppearance.onAccentColor ?? outgoingText }

    @MainActor
    static func outgoingBackground(olderBy count: Int, in environment: EnvironmentValues) -> Color {
        let accent = Reception.resolvedAppearance.accentColor
        guard Reception.resolvedAppearance.fadesOlderMessages, count > 0, environment.colorSchemeContrast != .increased else { return accent }
        let resolved = accent.resolve(in: environment)
        let fade = min(outgoingMaximumFade, Double(count) * outgoingFadeStep)
        // Tint only the fill so older bubbles soften without fading their text or photos.
        return Color(.sRGB,
                     red: Double(resolved.red) * (1 - fade) + fade,
                     green: Double(resolved.green) * (1 - fade) + fade,
                     blue: Double(resolved.blue) * (1 - fade) + fade,
                     opacity: Double(resolved.opacity))
    }

    static let error = Color.red
    static let foreground = Color.primary
    @MainActor static var incomingForeground: Color { Reception.resolvedAppearance.incomingForeground ?? foreground }
    static let muted = Color.secondary
    static let tertiary = Color(uiColor: .tertiaryLabel)

    @MainActor static func string(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: ReceptionLocalization.bundle)
    }
}
