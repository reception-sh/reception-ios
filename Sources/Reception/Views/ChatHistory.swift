import SwiftUI

internal struct ChatHistory: View {
    let model: ChatModel
    @State private var scrollRevision = 0
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
                                .id("support-typing")
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, Theme.spacing)
                    .padding(.top, Theme.small)
                    .frame(minHeight: viewport.size.height, alignment: .bottom)
                }
                .overlay { if model.messages.isEmpty { EmptyState() } }
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { _ in scrollRevision += 1 }
                .defaultScrollAnchor(.bottom)
                .scrollClipDisabled()
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: model.isTyping) { scrollRevision += 1 }
                .onChange(of: model.messages.last?.id) { scrollRevision += 1 }
                .onChange(of: model.isLoading) { if !model.isLoading { scrollRevision += 1 } }
                .task {
                    for await _ in NotificationCenter.default.notifications(named: UIResponder.keyboardDidChangeFrameNotification).map({ _ in () }) {
                        scrollRevision += 1
                    }
                }
                .task(id: scrollRevision) {
                    // Geometry callbacks invalidate this task after the new rows/insets have laid out.
                    await Task.yield()
                    guard !Task.isCancelled, let lastId = model.isTyping ? "support-typing" : model.messages.last?.id else { return }
                    proxy.scrollTo(lastId, anchor: .bottom)
                    do { try await Task.sleep(for: .seconds(Theme.layoutSettleDuration)) } catch { return }
                    guard !Task.isCancelled else { return }
                    proxy.scrollTo(lastId, anchor: .bottom)
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { _ in
                // Follow keyboard insets on iOS 18 after the viewport has changed.
                scrollRevision += 1
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
                        scrollRevision += 1
                    }
            }
        }
    }

    private func row(_ message: Message, at index: Int, width: CGFloat) -> some View {
        let isLast = message.id == model.messages.last?.id
        return MessageRow(message: message, availableWidth: width, layout: model.messageLayout(at: index), openReview: { url, action in model.openReview(url, messageId: message.id, using: action) },
                          canOpenPaywall: model.canOpenPaywall(message), openPaywall: { model.openPaywall(message) },
                          retryAvailability: model.retryAvailability(for: message),
                          cancelRetry: { model.cancelAutomaticRetry(messageId: message.id) }) {
            model.retry(messageId: message.id)
        }
        .padding(.bottom, isLast && !model.isTyping ? Theme.composerMessageGap : Theme.zero)
        .id(message.id)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { _ in
            if isLast { scrollRevision += 1 }
        }
        .transition(AnyTransition.move(edge: .bottom).combined(with: .opacity))
    }
}
