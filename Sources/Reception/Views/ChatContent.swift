import SwiftUI

@MainActor
internal struct ChatContent: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isPresented) private var isPresented
    @State private var model = Reception.shared.chatModel()

    var body: some View {
        ChatHistory(model: model)
        .background(Theme.background)
        .navigationTitle(Reception.resolvedAppearance.title)
        .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
        .tint(Reception.resolvedAppearance.accentColor)
        .toolbar {
            if #available(iOS 26, *) {
                    ToolbarItem(placement: .principal) { ChatTitle() }.sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .principal) { ChatTitle() }
                }
            if isPresented && Reception.resolvedAppearance.showsCloseButton {
                if #available(iOS 26, *) {
                    ToolbarItem(placement: .topBarTrailing) {
                        DismissButton { dismiss() }
                            .frame(width: Theme.toolbarControlDiameter, alignment: .trailing)
                            .offset(x: Theme.toolbarGlassCorrection)
                    }.sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .topBarTrailing) {
                        DismissButton { dismiss() }
                    }
                }
            }
        }
        .onAppear {
            model.isVisible = true
            Reception.shared.refreshPaywalls()
            Reception.shared.onEvent?(.chatOpened)
        }
        .task(id: Reception.shared.applicationActive) {
            guard Reception.shared.applicationActive else { model.stopPolling(); return }
            // Watch the network path before loading so an offline banner does not wait for the request.
            model.startMonitoring()
            await model.load(recheckLimits: true)
            guard !Task.isCancelled else { return }
            model.startPolling()
        }
        .onDisappear {
            model.stopPolling()
            model.isVisible = false
            Reception.shared.presenter.chatDidDisappear()
            Reception.shared.refreshUnread()
        }
    }
}
