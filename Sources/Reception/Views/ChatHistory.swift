import SwiftUI

internal struct ChatHistory: View {
    let model: ChatModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scrollRevision = 0
    /// Layout changes only scroll to the newest message while it is on screen, so a reader further up keeps their
    /// place after a Safari sheet, another app, a reload or a reply.
    @State private var scrollState = ChatScrollState()
    /// Set while the jump animation runs, so layout callbacks don't cut it short with an instant scroll.
    @State private var jumping = false
    @State private var jumps = 0
    @State private var composerHeight: CGFloat = Theme.zero

    var body: some View {
        ScrollViewReader { proxy in
            GeometryReader { viewport in
                ScrollView {
                    LazyVStack(spacing: Theme.zero) {
                        ForEach(Array(model.messages.enumerated()), id: \.element.id) { index, message in
                            row(message, at: index, width: viewport.size.width)
                        }
                        if model.pushPromptSlot != .none {
                            PushPromptSlotView(slot: model.pushPromptSlot, decline: { model.declinePushPrompt() },
                                               accept: { model.continuePushPrompt() })
                                .padding(.top, Theme.groupSpacing)
                                .padding(.bottom, model.isTyping ? Theme.zero : Theme.composerMessageGap)
                                .id(Self.pushPromptId)
                                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { _ in followNewest() }
                                .transition(.opacity)
                        }
                        if model.isTyping {
                            TypingIndicator()
                                .padding(.top, Theme.groupSpacing)
                                .padding(.bottom, Theme.composerMessageGap)
                                .id(Self.typingId)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .animation(Theme.messageAnimation, value: model.pushPromptSlot)
                    .padding(.horizontal, Theme.spacing)
                    .padding(.top, Theme.small)
                    .frame(minHeight: viewport.size.height, alignment: .bottom)
                }
                .overlay { if model.messages.isEmpty { EmptyState() } }
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { _ in followNewest() }
                .defaultScrollAnchor(.bottom)
                .pinnedToBottomOnSizeChanges()
                .scrollClipDisabled()
                .scrollDismissesKeyboard(.interactively)
                .withoutScrollEdgeEffects()
                .onChange(of: model.isTyping) { followNewest() }
                .onChange(of: model.pushPromptSlot) { followNewest() }
                .onChange(of: model.messages.map { ChatScrollState.Entry(id: $0.id, sender: $0.sender) }, initial: true) { _, entries in
                    if scrollState.messagesChanged(entries) { requestScroll() }
                }
                // A reply that lands while the chat is open taps the person lightly; the first load stays quiet.
                .sensoryFeedback(.impact(weight: .light), trigger: model.messages.last(where: { $0.sender == "AGENT" })?.id) { previous, current in
                    previous != nil && current != nil && model.isVisible
                }
                .onChange(of: model.isLoading) { if !model.isLoading { followNewest() } }
                .task {
                    // iOS 18 keeps the bottom pinned while the keyboard moves; iOS 17 needs a nudge once it has settled.
                    guard #unavailable(iOS 18) else { return }
                    for await _ in NotificationCenter.default.notifications(named: UIResponder.keyboardDidChangeFrameNotification).map({ _ in () }) {
                        followNewest()
                    }
                }
                .task(id: scrollRevision) {
                    // Geometry callbacks invalidate this task after the new rows/insets have laid out.
                    await Task.yield()
                    guard !Task.isCancelled, !jumping, let bottomId else { return }
                    withAnimation(Theme.messageAnimation) { proxy.scrollTo(bottomId, anchor: .bottom) }
                    do { try await Task.sleep(for: .seconds(Theme.layoutSettleDuration)) } catch { return }
                    guard !Task.isCancelled, !jumping else { return }
                    withAnimation(Theme.messageAnimation) { proxy.scrollTo(bottomId, anchor: .bottom) }
                }
                .task(id: jumps) {
                    guard jumps > 0, let bottomId else { return }
                    // One animated scroll to the row itself: the lazy stack lays out the rows on the way and lands
                    // exactly. Layout callbacks wait until it ends; an instant scroll would cut the animation short.
                    jumping = !reduceMotion
                    withAnimation(reduceMotion ? nil : Theme.jumpToLatestScrollAnimation) { proxy.scrollTo(bottomId, anchor: .bottom) }
                    try? await Task.sleep(for: .seconds(Theme.jumpToLatestScrollDuration))
                    jumping = false
                    requestScroll()
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { _ in
                // Follow keyboard insets on iOS 17 after the viewport has changed; iOS 18 pins the bottom itself.
                if #unavailable(iOS 18) { followNewest() }
            }
            .mask(alignment: .top) {
                VStack(spacing: Theme.zero) {
                    LinearGradient(colors: [.clear, Theme.foreground], startPoint: .top, endPoint: .bottom)
                        .frame(height: Theme.headerFadeHeight)
                    Rectangle()
                }
                .padding(.top, -Theme.headerFadeOverlap)
                // Rows drawn past the frame show through the glass composer down to the sheet's edge, like Messages.
                .padding(.bottom, -(composerHeight + Self.homeIndicatorInset))
            }
            .overlay(alignment: .bottom) {
                ZStack {
                    if scrollState.showsJumpControl {
                        JumpToLatestButton(unseenCount: scrollState.unseenCount, action: jumpToNewest)
                            .padding(.bottom, Theme.jumpToLatestGap)
                            .transition(reduceMotion ? .opacity : .offset(y: Theme.jumpToLatestRise).combined(with: .opacity))
                    }
                }
                .animation(Theme.messageAnimation, value: scrollState.showsJumpControl)
                .sensoryFeedback(.impact(weight: .light), trigger: jumps)
            }
            .safeAreaInset(edge: .bottom, spacing: Theme.zero) {
                VStack(spacing: Theme.zero) {
                    if model.connection != .hidden {
                        ConnectionBanner(state: model.connection)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, Theme.spacing)
                            .padding(.bottom, Theme.spacing)
                            .transition(.opacity)
                    }
                    if let cooldown = model.composerCooldown, !model.sendingDisabled, !model.verificationRequired {
                        CooldownNotice(cooldown: cooldown)
                            .padding(.horizontal, Theme.spacing)
                            .padding(.bottom, Theme.small)
                            .transition(.opacity)
                    }
                    // Starting to write shows the newest message, like Messages.
                    Composer(chat: model, onFocus: { requestScroll() })
                }
                    .animation(Theme.messageAnimation, value: model.connection)
                    .animation(Theme.messageAnimation, value: model.composerCooldown)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                        composerHeight = height
                        followNewest()
                    }
            }
        }
    }

    private static let typingId = "support-typing"
    private static let pushPromptId = "push-prompt"

    /// The sheet reaches the bottom of the window, so the window's inset is the strip below the composer; the keyboard
    /// never changes it, unlike the view's own safe area.
    private static var homeIndicatorInset: CGFloat {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
            .first(where: \.isKeyWindow)?.safeAreaInsets.bottom ?? Theme.zero
    }

    /// The lowest row, which scrolling keeps above the composer.
    private var bottomId: String? {
        if model.isTyping { return Self.typingId }
        return model.pushPromptSlot == .none ? model.messages.last?.id : Self.pushPromptId
    }

    private func followNewest() {
        if scrollState.followsNewest { requestScroll() }
    }

    private func requestScroll() {
        if !jumping { scrollRevision += 1 }
    }

    private func jumpToNewest() {
        scrollState.jumpedToNewest()
        jumps += 1
    }

    private func row(_ message: Message, at index: Int, width: CGFloat) -> some View {
        let isLast = message.id == model.messages.last?.id
        return MessageRow(message: message, availableWidth: width, layout: model.messageLayout(at: index), openReview: { url, action in model.openReview(url, messageId: message.id, using: action) },
                          linkOpensInApp: message.linkCardURL.map { model.isHostLink($0) } ?? false,
                          openLink: { url in model.openLink(url, messageId: message.id) }, openTextLink: model.openTextLink,
                          canOpenPaywall: model.canOpenPaywall(message), openPaywall: { model.openPaywall(message) },
                          retryAvailability: model.retryAvailability(for: message),
                          cancelRetry: { model.cancelAutomaticRetry(messageId: message.id) }) {
            model.retry(messageId: message.id)
        }
        .padding(.bottom, isLast && !model.isTyping && model.pushPromptSlot == .none ? Theme.composerMessageGap : Theme.zero)
        .id(message.id)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { _ in
            if isLast { followNewest() }
        }
        // On screen means inside the scroll view's visible bounds: a lazy stack also builds rows just outside them, so
        // onAppear would count the newest row as seen while the reader is further up.
        .onGeometryChange(for: Bool.self) { proxy in
            proxy.bounds(of: .scrollView)?.intersects(CGRect(origin: .zero, size: proxy.size)) ?? false
        } action: { isVisible in
            if isLast { scrollState.newest(message.id, isVisible: isVisible) }
        }
        .transition(AnyTransition.move(edge: .bottom).combined(with: .opacity))
    }
}

private extension View {
    /// Like Messages, the newest message stays put while the keyboard moves or a message arrives: iOS 18 keeps the
    /// bottom anchored through size changes instead of scrolling back after the fact.
    @ViewBuilder func pinnedToBottomOnSizeChanges() -> some View {
        if #available(iOS 18, *) { defaultScrollAnchor(.bottom, for: .sizeChanges) } else { self }
    }

    /// iOS 26 paints hard bands where content scrolls under the bar and the composer; the history fades its own
    /// top instead, and the glass composer shows what passes beneath it.
    @ViewBuilder func withoutScrollEdgeEffects() -> some View {
        if #available(iOS 26, *) { scrollEdgeEffectHidden() } else { self }
    }
}
