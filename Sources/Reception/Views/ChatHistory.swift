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
                        if model.isTyping {
                            TypingIndicator()
                                .padding(.top, Theme.groupSpacing)
                                .padding(.bottom, Theme.composerMessageGap)
                                .id(Self.typingId)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, Theme.spacing)
                    .padding(.top, Theme.small)
                    .frame(minHeight: viewport.size.height, alignment: .bottom)
                }
                .overlay { if model.messages.isEmpty { EmptyState() } }
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { _ in followNewest() }
                .defaultScrollAnchor(.bottom)
                .scrollClipDisabled()
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: model.isTyping) { followNewest() }
                .onChange(of: model.messages.map { ChatScrollState.Entry(id: $0.id, sender: $0.sender) }, initial: true) { _, entries in
                    if scrollState.messagesChanged(entries) { requestScroll() }
                }
                .onChange(of: model.isLoading) { if !model.isLoading { followNewest() } }
                .task {
                    for await _ in NotificationCenter.default.notifications(named: UIResponder.keyboardWillShowNotification).map({ _ in () }) {
                        requestScroll()
                    }
                }
                .task {
                    for await _ in NotificationCenter.default.notifications(named: UIResponder.keyboardDidChangeFrameNotification).map({ _ in () }) {
                        followNewest()
                    }
                }
                .task(id: scrollRevision) {
                    // Geometry callbacks invalidate this task after the new rows/insets have laid out.
                    await Task.yield()
                    guard !Task.isCancelled, !jumping, let newestId else { return }
                    proxy.scrollTo(newestId, anchor: .bottom)
                    do { try await Task.sleep(for: .seconds(Theme.layoutSettleDuration)) } catch { return }
                    guard !Task.isCancelled, !jumping else { return }
                    proxy.scrollTo(newestId, anchor: .bottom)
                }
                .task(id: jumps) {
                    guard jumps > 0, let newestId else { return }
                    // One animated scroll to the row itself: the lazy stack lays out the rows on the way and lands
                    // exactly. Layout callbacks wait until it ends; an instant scroll would cut the animation short.
                    jumping = !reduceMotion
                    withAnimation(reduceMotion ? nil : Theme.jumpToLatestScrollAnimation) { proxy.scrollTo(newestId, anchor: .bottom) }
                    try? await Task.sleep(for: .seconds(Theme.jumpToLatestScrollDuration))
                    jumping = false
                    requestScroll()
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { _ in
                // Follow keyboard insets on iOS 18 after the viewport has changed.
                followNewest()
            }
            .mask(alignment: .top) {
                VStack(spacing: Theme.zero) {
                    LinearGradient(colors: [.clear, Theme.foreground], startPoint: .top, endPoint: .bottom)
                        .frame(height: Theme.headerFadeHeight)
                    Rectangle()
                }
                .padding(.top, -Theme.headerFadeOverlap)
                .padding(.bottom, -composerHeight)
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
                    Composer(chat: model)
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

    private var newestId: String? { model.isTyping ? Self.typingId : model.messages.last?.id }

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
        .padding(.bottom, isLast && !model.isTyping ? Theme.composerMessageGap : Theme.zero)
        .id(message.id)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { _ in
            if isLast { followNewest() }
        }
        .onAppear { if isLast { scrollState.newest(message.id, isVisible: true) } }
        .onDisappear { if isLast { scrollState.newest(message.id, isVisible: false) } }
        .transition(AnyTransition.move(edge: .bottom).combined(with: .opacity))
    }
}
