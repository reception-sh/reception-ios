import SwiftUI

internal struct MessageBubble: View {
    @Environment(\.self) private var environment
    let message: Message
    let availableWidth: CGFloat
    let showsDeliveryStatus: Bool
    let olderOutgoingCount: Int
    let openReview: (URL, OpenURLAction) -> Void
    let canOpenPaywall: Bool
    let openPaywall: () -> Void
    let retryAvailability: RetryAvailability
    let cancelRetry: () -> Void
    let retry: () -> Void
    @ScaledMetric(relativeTo: .caption) private var statusSize = Theme.deliveryStatusSize
    @ScaledMetric(relativeTo: .body) private var failureSize = Theme.failureIconSize
    @State private var selected: Attachment?

    var body: some View {
        HStack(spacing: Theme.zero) {
            if message.sender == "USER" { Spacer(minLength: Theme.control) }
            VStack(alignment: message.sender == "USER" ? .trailing : .leading, spacing: Theme.deliveryStatusSpacing) {
                HStack(alignment: .center, spacing: Theme.small) {
                    if message.status == .failed && canRetry {
                        Button(action: retry) { failureIcon }.accessibilityLabel(Theme.string("Retry"))
                    } else if message.status == .failed {
                        // A cooldown holds the message; the status line below states it and its retry.
                        failureIcon.accessibilityHidden(true)
                    }
                    if message.kind == "REVIEW", let url = message.reviewUrl {
                        ReviewCard(text: message.text, label: message.buttonLabel, url: url, openReview: openReview)
                    } else if message.kind == "PAYWALL" {
                        PaywallCard(text: message.text, label: message.buttonLabel, isAvailable: canOpenPaywall, openPaywall: openPaywall)
                    } else {
                        bubbles
                    }
                }
                if message.status == .failed {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: Theme.small) { failureStatus }
                        VStack(alignment: .trailing, spacing: Theme.deliveryStatusSpacing) { failureStatus }
                    }.font(Theme.textFont(size: Theme.deliveryStatusSize, scaledSize: statusSize, relativeTo: .caption))
                } else if showsDeliveryStatus && (message.status == .sent || message.showsPending) {
                    Group {
                        if message.status == .sent { Text(Theme.string("Sent")) }
                        else { SendingStatus() }
                    }
                        .font(Theme.textFont(size: Theme.deliveryStatusSize, scaledSize: statusSize, relativeTo: .caption)).foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.trailing).contentTransition(.opacity)
                        .transition(.opacity)
                }
            }
            .animation(Theme.deliveryStatusAnimation, value: message.status)
            .animation(Theme.deliveryStatusAnimation, value: message.showsPending)
            .animation(Theme.deliveryStatusAnimation, value: showsDeliveryStatus)
            if message.sender != "USER" { Spacer(minLength: Theme.control) }
        }
        .animation(Theme.messageAnimation, value: message.status)
        .fullScreenCover(item: $selected) { ImageLightbox(attachment: $0) }
    }

    private var canRetry: Bool { retryAvailability == .now }

    private var failureIcon: some View {
        Image(systemName: "exclamationmark.circle.fill").resizable().scaledToFit()
            .frame(width: failureSize, height: failureSize).foregroundStyle(Theme.error)
    }

    private var failureStatus: some View {
        Group {
            Text(Theme.string("Not delivered")).foregroundStyle(Theme.error)
            if case .automatic(let until) = retryAvailability {
                TimelineView(Theme.countdownTicks) { context in
                    Text(CooldownText.resend(until: until, now: context.date)).foregroundStyle(Theme.muted)
                }
                Button(Theme.string("Cancel"), action: cancelRetry)
                    .foregroundStyle(Reception.resolvedAppearance.accentColor)
                    .accessibilityLabel(Theme.string("Cancel automatic sending"))
            } else {
                Button(Theme.string("Retry"), action: retry)
                    .foregroundStyle(canRetry ? Reception.resolvedAppearance.accentColor : Theme.muted)
                    .disabled(!canRetry)
            }
        }
    }

    private var bubbles: some View {
        VStack(alignment: message.sender == "USER" ? .trailing : .leading, spacing: Theme.groupedSpacing) {
            if !message.text.isEmpty {
                if message.status == .failed && canRetry {
                    Button(action: retry) { textBubble }.buttonStyle(.plain)
                        .accessibilityHint(Theme.string("Retry"))
                } else { textBubble.textSelection(.enabled) }
            }
            ForEach(message.attachments) { attachment in
                MessageImage(attachment: attachment, maximumWidth: imageWidth, openPhoto: {
                    if message.status != .failed { selected = attachment } else if canRetry { retry() }
                })
            }
            if message.attachments.isEmpty {
                ForEach(message.images.indices, id: \.self) { index in
                    if message.status == .failed && canRetry {
                        Button(action: retry) { MessageImage(image: message.images[index], maximumWidth: imageWidth) }
                            .buttonStyle(.plain).accessibilityLabel(Theme.string("Retry"))
                    } else {
                        MessageImage(image: message.images[index], maximumWidth: imageWidth)
                    }
                }
            }
        }
        .opacity(message.sender == "USER" && message.status == .sending && message.showsPending ? Theme.sendingOpacity : Theme.fullOpacity)
    }

    private var imageWidth: CGFloat { availableWidth * Theme.imageWidthFraction }

    private var textBubble: some View {
        Text(message.text).font(Theme.bodyFont)
            .foregroundStyle(message.sender == "USER" ? Theme.outgoingForeground : Theme.incomingForeground)
            .padding(.horizontal, Theme.bubbleHorizontal).padding(.vertical, Theme.bubbleVertical)
            .background(message.sender == "USER" ? Theme.outgoingBackground(olderBy: olderOutgoingCount, in: environment) : Theme.secondary, in: BubbleShape())
    }
}
