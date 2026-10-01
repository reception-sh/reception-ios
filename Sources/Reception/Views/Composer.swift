import SwiftUI
import PhotosUI

internal struct Composer: View {
    let chat: ChatModel
    @Bindable private var model: ComposerModel
    @State private var keyboardVisible = false
    @State private var fieldHeight: CGFloat = Theme.zero

    @State private var availableWidth = Theme.composerReferenceWidth
    private var dimensions = ComposerDimensions()
    private var sizes: ComposerDimensions.Values { dimensions.resolve(width: availableWidth, keyboard: keyboardVisible) }
    private var multiline: Bool { fieldHeight > sizes.innerHeight + Theme.unit }
    private var hasContent: Bool { !model.text.isEmpty || !model.photos.isEmpty }
    private var sendable: Bool { model.canSend && chat.canSend && chat.cooldownAllowsSend(photos: !model.photos.isEmpty) }

    init(chat: ChatModel) { self.chat = chat; self.model = chat.composer }

    var body: some View {
        ZStack(alignment: .bottom) {
            if chat.sendingDisabled {
                SendingDisabledNotice(text: Theme.string("Messages can't be sent from this device right now."),
                                      height: sizes.height).transition(.opacity)
            } else if chat.verificationRequired {
                SendingDisabledNotice(text: Theme.string("Sign in to send messages."), height: sizes.height)
                    .transition(.opacity)
            } else if #available(iOS 26, *) {
                GlassEffectContainer(spacing: sizes.gap) { composer }.transition(.opacity)
            } else {
                composer.transition(.opacity)
            }
        }
        .animation(Theme.sendingDisabledAnimation, value: chat.sendingDisabled)
        .animation(Theme.sendingDisabledAnimation, value: chat.verificationRequired)
        .padding(.leading, sizes.leading)
        .padding(.trailing, sizes.trailing)
        .padding(.bottom, sizes.bottom)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
        .task {
            for await height in NotificationCenter.default.notifications(named: UIResponder.keyboardWillShowNotification)
                .compactMap({ ($0.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect)?.height }) {
                keyboardVisible = height > Theme.zero
            }
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: UIResponder.keyboardWillHideNotification).map({ _ in () }) {
                keyboardVisible = false
            }
        }
        .onChange(of: chat.sendingDisabled) { if chat.sendingDisabled { keyboardVisible = false } }
        .onChange(of: chat.verificationRequired) { if chat.verificationRequired { keyboardVisible = false } }
        .task(id: model.selection) { await model.loadSelection() }
    }

    private var composer: some View {
        let sizes = self.sizes
        let multiline = self.multiline
        let photoForeground = chat.photosPaused ? Theme.muted : Theme.foreground
        return VStack(spacing: sizes.small) {
            if !model.photos.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: sizes.small) {
                        ForEach(model.photos) { photo in
                            Image(uiImage: photo.image).resizable().scaledToFill()
                                .frame(width: sizes.chip, height: sizes.chip).clipShape(RoundedRectangle(cornerRadius: sizes.small))
                                .overlay {
                                    RoundedRectangle(cornerRadius: sizes.small)
                                        .strokeBorder(Theme.imageBorder, lineWidth: Theme.imageBorderWidth)
                                        .allowsHitTesting(false)
                                }
                                .overlay(alignment: .topTrailing) {
                                    Button { model.remove(photo.id) } label: {
                                        Image(systemName: "xmark.circle.fill").symbolRenderingMode(.palette)
                                            .foregroundStyle(Theme.background, Theme.foreground)
                                    }.accessibilityLabel(Theme.string("Remove photo"))
                                }
                        }
                    }.padding(sizes.small)
                }
            }
            if let progress = chat.uploadProgress {
                ProgressView(value: progress)
                    .padding(.horizontal, Theme.uploadProgressHorizontalInset)
                    .accessibilityLabel(Theme.string("Uploading photos"))
            }
            if let error = model.error { Text(error).font(Theme.captionFont).foregroundStyle(Theme.error) }
            HStack(alignment: .bottom, spacing: sizes.gap) {
                PhotosPicker(selection: $model.selection, maxSelectionCount: max(1, 5 - model.photos.count), matching: .images) {
                    Image(systemName: "photo.on.rectangle").font(.system(size: sizes.photoIcon))
                        .frame(width: sizes.photo, height: sizes.photo)
                        .foregroundStyle(photoForeground).modifier(ComposerButtonSurface())
                        .contentShape(Circle())
                        .padding(.bottom, sizes.vertical + sizes.buttonBottom(sizes.photo, multiline: multiline))
                }.disabled(model.photos.count >= 5 || model.loading || chat.photosPaused)
                    .accessibilityLabel(Theme.string("Add photos"))
                field
            }
            .buttonStyle(.plain)

            if model.loading { ProgressView().accessibilityLabel(Theme.string("Loading photos")) }
            if model.text.utf16.count > 4000 {
                Text(Theme.string("Messages can contain up to 4,000 characters.")).font(Theme.captionFont).foregroundStyle(Theme.error)
            }
        }

    }

    private var field: some View {
        HStack(alignment: .bottom, spacing: sizes.small) {
            TextField(text: $model.text, axis: .vertical) {
                Text(Theme.string("Message")).lineLimit(1)
            }
                .font(Theme.textFont(size: Theme.bodySize, scaledSize: sizes.textSize)).lineLimit(1...Theme.composerLineLimit)
                .frame(minHeight: sizes.innerHeight)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fieldHeight = $0 }
            if hasContent {
                Button { model.send(to: chat) } label: {
                    Image(systemName: "arrow.up").font(.system(size: sizes.sendIcon, weight: .bold))
                        .frame(width: sizes.sendWidth, height: sizes.sendHeight)
                        .foregroundStyle(sendable ? Theme.outgoingForeground : Theme.muted)
                        .background(sendable ? Reception.resolvedAppearance.accentColor : Theme.composerDisabled, in: Capsule())
                        .contentShape(Capsule())
                }
                .disabled(!sendable).accessibilityLabel(Theme.string("Send message"))
                .padding(.bottom, sizes.buttonBottom(sizes.sendHeight, multiline: multiline))
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.leading, sizes.textLeading)
        .padding(.trailing, sizes.sendInset)
        .padding(.vertical, sizes.vertical)
        .frame(minHeight: sizes.height)
        .modifier(ComposerSurface(multiline: multiline, radius: sizes.radius))
        .animation(Theme.sendButtonAnimation, value: hasContent)
    }
}
